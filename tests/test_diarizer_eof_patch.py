import hashlib,json,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
P=ROOT/'probes/diarizer-eof'
class EOFDiagnosticTests(unittest.TestCase):
    def test_patch_hash_and_scope(self):
        manifest=json.loads((P/'manifest.json').read_text())
        patch=(P/'fluid-eof.patch').read_bytes()
        self.assertEqual(hashlib.sha256(patch).hexdigest(),manifest['patchSHA256'])
        self.assertEqual(len(manifest['files']),2)
        self.assertEqual(sum(line.startswith('+++ b/') for line in patch.decode().splitlines()),2)
        self.assertIn('end <= duration + 0.05',(ROOT/'VoiceMatrix/LocalSpeakerPolicy.swift').read_text())
    def test_native_boundary_cases_exist(self):
        s=(P/'EOFTimelineTests.swift').read_text()
        for name in ['ExactEOF','PartialFinalFrameOnlyIntersectsExistingAudio','PaddingDoesNotBecomeSpeechAtEOF','UnalignedPaddingDoesNotVoteIntoLastFrame','RealOverlapRemainsOverlap','InvalidAudioBoundsFailClosed','RealSpeechEndingBeforeEOFNotExtended']:
            self.assertIn('func test'+name+'()',s)
    def test_wrong_revision_is_rejected_without_mutation(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); checkout=root/'dependency';checkout.mkdir()
            subprocess.run(['git','init','-q',str(checkout)],check=True)
            subprocess.run(['git','-C',str(checkout),'-c','user.name=Test','-c','user.email=test@example.invalid','commit','--allow-empty','-qm','Test'],check=True)
            result=subprocess.run(['python3',str(P/'apply.py'),str(checkout),str(root/'proof')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Unexpected dependency revision',result.stderr)
            self.assertFalse((root/'proof').exists())
            self.assertEqual(subprocess.check_output(['git','-C',str(checkout),'status','--porcelain'],text=True),'')
    def test_actual_app_boundary_guard_still_rejects_invalid_evidence(self):
        source='''import Foundation
@main struct Check { static func main() throws {
 let duration = 36.5993125
 _ = try LocalSpeakerPolicy.speakerWindows([.init(speaker:"S1",start:29.3548,end:duration)],duration:duration)
 for end in [duration+0.050001,36.68930435180664,Double.infinity,Double.nan] {
  do { _ = try LocalSpeakerPolicy.speakerWindows([.init(speaker:"S1",start:29.3548,end:end)],duration:duration)
   fatalError("Out-of-source evidence accepted")
  } catch LocalSpeakerPolicy.Failure.invalidEvidence {}
 }
 print("Actual app EOF guard unchanged; beyond-boundary evidence rejected")
}}
'''
        with tempfile.TemporaryDirectory() as t:
            p=pathlib.Path(t);(p/'Check.swift').write_text(source)
            subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/LocalSpeakerPolicy.swift'),str(p/'Check.swift'),'-o',str(p/'check')],check=True)
            subprocess.run([str(p/'check')],check=True)
