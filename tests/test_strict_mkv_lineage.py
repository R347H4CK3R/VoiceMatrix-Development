from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "VoiceMatrix"

class StrictMKVLineageTests(unittest.TestCase):
    def test_clip_and_reference_persist_only_verified_derived_lineage(self):
        for name, needles in {
            "SeparationClipHandoff.swift": ["matroskaLineage", "validMatroskaLineage"],
            "ClipSpeakerReviewStore.swift": ["receipt.matroskaLineage == source.matroskaLineage"],
            "CharacterFolderStore.swift": ["var matroskaReference:", "validMatroskaReference"],
            "LocalVideoStudio.swift": ["strictSourceLineage", "matroskaReference", "existing.matroskaReference"],
        }.items():
            text = (ROOT / name).read_text()
            for needle in needles: self.assertIn(needle, text)

    def test_separated_vocals_chain_crosses_every_persisted_hop(self):
        cases = {
            "SeparationClipHandoff.swift": ["verifiedLineage", "input.receiptSHA256"],
            "VocalSeparationView.swift": ["acceptedClip = nil", "verifiedLineage(clip", "clipLineage: lineage"],
            "SeparationStore.swift": ["clipLineage?.valid(inputSHA256: inputSHA256, frames: vocals.count / 2)", "clipLineage:current.receipt.clipLineage"],
            "LocalVideoStudio.swift": ["separatedMatroska = referenceInput", "selectedReferenceStart", "separatedClip: separatedLineage?.clip"],
            "MatroskaSourceLineage.swift": ["clipReceiptSHA256", "let vocalsSHA256:", "Double(clip.frames) / 44_100"]
        }
        missing = [(name, needle) for name, needles in cases.items()
                   for needle in needles if needle not in (ROOT / name).read_text()]
        self.assertEqual(missing, [])

    def test_standalone_native_separator_build_includes_provenance_type(self):
        project = (ROOT.parent / "probes/vocal-separation-native/project.yml").read_text()
        self.assertIn("SeparationStore.swift", project)
        self.assertIn("MatroskaSourceLineage.swift", project)

    def test_first_product_commit_validates_published_tuple_after_derivation(self):
        studio = (ROOT / "LocalVideoStudio.swift").read_text()
        run = studio.index("let output = try await LocalMatroskaWorkflow.run")
        record = studio.index("current?.sourceFile = output.derived.file", run)
        self.assertIn("LocalMatroskaWorkflow.validatePublished", studio[run:record])

    def test_strict_profile_provenance_rejects_more_than_ten_seconds(self):
        lineage = (ROOT / "MatroskaSourceLineage.swift").read_text()
        profile = lineage[lineage.index("struct MatroskaReferenceLineage:"):]
        self.assertIn("(0.5...10).contains(requestedDurationSeconds)", profile)
        self.assertIn("(10_800...240_000).contains(retainedFrames)", profile)

    def test_isolated_native_gate_requires_named_lineage_and_job_evidence(self):
        gate = (ROOT.parent / ".github/workflows/strict-mkv-workflow.yml").read_text()
        self.assertIn("github.ref == 'refs/heads/verification/strict-mkv-workflow'", gate)
        self.assertIn("contents: read", gate)
        self.assertIn("persist-credentials: false", gate)
        for suite, name in {
            "StrictMatroskaJobTests": "testStrictJobAcceptsOnlyCompleteDerivedSourceBinding",
            "StrictMatroskaLineageTests": "testSeparatedVocalsReceiptAndReferenceKeepClipHashAndAbsoluteTime",
        }.items():
            self.assertIn(f"-only-testing:VoiceMatrixTests/{suite}", gate)
            self.assertIn(name, gate)
        self.assertIn("probes/mkv-workflow/verify.py", gate)
        self.assertIn("strict-mkv-licensed.mp4", gate)

    def test_real_media_gate_requires_committed_clip_receipt_and_payload(self):
        root = ROOT.parent
        native = (root / "VoiceMatrixTests/LocalMatroskaWorkflowMediaTests.swift").read_text()
        oracle = (root / "probes/mkv-workflow/verify.py").read_text()
        self.assertIn("SeparationClipHandoff.prepare", native)
        self.assertIn("SeparationClipHandoff.verifiedLineage", native)
        for artifact in ("committed-clip.wav", "committed-clip-receipt.json"):
            self.assertIn(artifact, native)
            self.assertIn(artifact, oracle)
        self.assertIn('assert committed["matroskaLineage"]', oracle)

    def test_studio_explains_strict_mkv_and_explicit_file_import(self):
        view = (ROOT / "LocalVideoStudioView.swift").read_text()
        section = view.split('DisclosureGroup("What this can do")', 1)[1].split("if let mkvExport", 1)[0]
        self.assertIn("New links", section)
        self.assertIn("verified MKV", section)
        self.assertIn("the app stops and keeps any files it saved", section)
        self.assertIn("choose a local file you have permission to use", section)
        self.assertIn("Older saved jobs", section)
        self.assertIn("does not identify characters", section)
        self.assertNotIn("verified MP4 fallback", section)
        self.assertNotIn("Analysis uses the MP4 companion", section)

    def test_native_gate_runs_history_recovery_with_swift_available(self):
        gate = (ROOT.parent / ".github/workflows/strict-mkv-workflow.yml").read_text()
        self.assertIn("command -v swiftc", gate)
        self.assertIn("tests.test_local_snapshot_recovery", gate)

    def test_fixture_injection_targets_only_the_native_test_bundle(self):
        import subprocess
        import sys
        import tempfile
        import yaml

        root = ROOT.parent
        workflow = yaml.safe_load((root / ".github/workflows/strict-mkv-workflow.yml").read_text())
        step = next(step for step in workflow["jobs"]["app-integration"]["steps"]
                    if step.get("name") == "Prepare verified tooling and source-only resources")
        script = step["run"].split("<<'PY_RESOURCE'\n", 1)[1].split("\nPY_RESOURCE", 1)[0]
        source = (root / "project.yml").read_text()
        self.assertIn("    - VoiceMatrixTests\n", source)
        self.assertIn("      - VoiceMatrixTests\n", source)
        before = yaml.safe_load(source)
        resources = [{"path": f".strict-mkv-fixture/{name}", "buildPhase": "resources"}
                     for name in ("strict-mkv-licensed.mp4", "strict-mkv-fixture.json")]
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project.yml"
            project.write_text(source)
            run = subprocess.run([sys.executable, "-c", script], cwd=directory, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr.decode())
            after = yaml.safe_load(project.read_text())
            original_sources = before["targets"]["VoiceMatrixTests"]["sources"]
            self.assertEqual(after["targets"]["VoiceMatrixTests"]["sources"],
                             [original_sources[0], *resources, *original_sources[1:]])
            after["targets"]["VoiceMatrixTests"]["sources"] = original_sources
            self.assertEqual(after, before)
            broken = source.replace("    sources:\n    - VoiceMatrixTests\n",
                                    "    sources:\n    - UnrelatedTests\n", 1)
            project.write_text(broken)
            rejected = subprocess.run([sys.executable, "-c", script], cwd=directory, capture_output=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual(project.read_text(), broken)

    def test_native_collection_boots_the_exact_test_simulator_before_reading(self):
        import subprocess
        import tempfile
        import yaml

        workflow = yaml.safe_load((ROOT.parent / ".github/workflows/strict-mkv-workflow.yml").read_text())
        run = next(step["run"] for step in workflow["jobs"]["app-integration"]["steps"]
                   if step.get("name") == "Run actual Python, MKV remux, derivation and clip extraction")
        collect = run.split("\nPY_GATE\n", 1)[1].split("\ncp -R ", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            mock = r'''
            set -euo pipefail
            DEVICE=01234567-89AB-4CDE-F012-3456789ABCDE
            xcrun() {
                test "$1" = simctl
                test "$3" = "$DEVICE"
                case "$2" in
                    bootstatus) test "$4" = -b; touch booted;;
                    get_app_container)
                        if ! test -f booted; then echo "Unable to lookup in current state: Shutdown" >&2; return 1; fi
                        test "$4" = com.voicematrix.app
                        test "$5" = data
                        printf '/expected/owned/container\n';;
                    *) return 1;;
                esac
            }
            '''
            result = subprocess.run(["bash", "-c", mock + collect +
                                     '\ntest "$CONTAINER" = /expected/owned/container\n'],
                                    cwd=directory, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((Path(directory) / "booted").is_file())
