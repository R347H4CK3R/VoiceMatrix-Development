from tools.test_shell import check_bash_syntax
import pathlib,subprocess,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RetainedSpeechDiagnosticTests(unittest.TestCase):
    def test_exact_audio_and_recognizer_no_regeneration(self):
        p=(ROOT/'probes/retained-new-speech-asr/Sources/Probe/Probe.swift').read_text()
        self.assertIn('fe750049af1dc3f52ca50d3d9f6b3411a9154417a7e53b1df26fb687a47e541a',p)
        self.assertIn('let accepted=wer<=0.1 && matches',p)
        self.assertLess(p.index('try encoder.encode(Report'),p.index('guard accepted'))
        self.assertIn('let recognizer=OnDeviceTranscription(bundle:models)',p)
        self.assertNotIn('synthesize',p)
    def test_bounded_network_denied_readonly_workflow(self):
        w=yaml.safe_load((ROOT/'.github/workflows/retained-new-speech-asr.yml').read_text())
        self.assertEqual(w['permissions'],{'contents':'read','actions':'read'})
        self.assertEqual(w['jobs']['diagnose']['timeout-minutes'],25)
        s='\n'.join(x.get('run','') for x in w['jobs']['diagnose']['steps'])
        self.assertIn('(deny network*)',s)
        self.assertIn('b3623b6847223e0c0704aa60a896b746d733b141152478534200fcfeb19e6779',s)
        for step in w['jobs']['diagnose']['steps']:
            if 'run' in step: check_bash_syntax(step['run'])
