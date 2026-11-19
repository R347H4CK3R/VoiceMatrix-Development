# Narrow native original-frontend production-route diagnostic

No CI was launched by this harness preparation. It does not make an iOS,
physical-device, general ASR, broader pipeline, publishing, or redistribution
claim. Review the candidate source and immutable model/fixture provenance before
using it on a dedicated runner.

## Inputs and exact recipe

- Exact reviewed candidate source tree/commit, including the package manifest,
  diagnostic source, offline preparer, reviewed app wrapper/policy/assets/evidence,
  and local vendored FluidAudio with the four adapter seam Swift files. A
  surrounding run must bind the whole reviewed tree; the preparer records hashes
  but does not independently verify the commit from the supplied ID.
- The original v3 two-buffer and mattt converted artifact package, independently
  staged using the reviewed model stager and exact lock **before** recognition.
  See `docs/asr-original-frontend/` for the frontend provenance, licenses and
  API note about the now-optional CoreML `preprocessor` getter. Neither this
  preparer nor recognizer downloads assets.
- Existing `tests/fixtures/conversion-source.wav` and
  `conversion-reference.wav` exactly size/hash-pinned. They are not new speech.
- Existing unchanged `probes/reference-context-human-holdouts/prepare.py` and
  `sources.json`, including four independently fixed CC BY 4.0 LibriSpeech
  FLACs (total 486,462 bytes), exact checksums and whole-source FFmpeg decode.
  Their preselected IDs, source revision, corpus labels, and same full WAV
  in both production modes must stay unchanged. Keep the FLAC files in the
  private prepared human fixture directory: the native harness checks their
  exact hashes and lengths too. It also checks WAV hash and decoded frame count.
- The preparer authors only an exact one-second mono/16k/PCM16 silence WAV as
  negative control; no generated or new speech is introduced. Both mode calls
  must return exactly `.noSpeech`, nil evidence, and no success activity.

Example execution from an authorized, already provisioned isolated workspace:

```bash
set -euo pipefail
ROOT="$(pwd)"
STAGE="$RUNNER_TEMP/asr-diagnostic-work"
HUMAN="$RUNNER_TEMP/asr-pinned-human"
MODELS="$RUNNER_TEMP/asr-reviewed-models"  # complete reviewed staged asset root
EVIDENCE="$RUNNER_TEMP/asr-evidence"     # new, mode 0700, no input/output audio
mkdir -m 700 "$EVIDENCE"
python3 probes/native-original-asr/prepare_diagnostic.py "$STAGE" "$CANDIDATE_SHA"
cp "$STAGE/source-proof.json" "$EVIDENCE/source-proof.json"
# Run the existing corpus preparer only after explicit authorization for fixture access.
python3 probes/reference-context-human-holdouts/prepare.py "$HUMAN" 2>&1 | tee "$EVIDENCE/human-preparation.log"
cp "$HUMAN/manifest.json" "$EVIDENCE/human-manifest.json"
swift build --package-path "$STAGE/probes/native-original-asr" -c release \
    2>&1 | tee "$EVIDENCE/build.log"
PROBE="$(swift build --package-path "$STAGE/probes/native-original-asr" -c release --show-bin-path)/Probe"
sandbox-exec -p '(version 1)(allow default)(deny network*)' "$PROBE" \
    "$STAGE/fixtures" "$HUMAN" "$MODELS" "$EVIDENCE/result.json" "$CANDIDATE_SHA" \
    2>&1 | tee "$EVIDENCE/recognition.log"
```

A pass requires all 12 rows: two earlier speech rows at WER ≤ 0.1, all
eight human mode receipts at WER 0, and both silence modes. It also requires
rejection of the existing ~20 ms cancellation test, no cancelled success
activity/evidence, and success of the first post-cancellation retry with the
same input. Speech calls must match original WAV hash, transcript hash, exact
model revision, 250 ms reference-only context (zero baseline context),
one success activity and real finite token evidence. Supplied corpus text is
used only after transcription to score recognition. No modified time/cancel policy.

The status string `NARROW_PRODUCTION_ASR_FIXTURES_PASSED_NO_DEVICE_CLAIM`
identifies only a passing native result for these cases. Upload narrow logs,
source/provenance manifests, and JSON report only. Never upload the human/audio
input directories, model package, or compiled binary as diagnostic evidence.
