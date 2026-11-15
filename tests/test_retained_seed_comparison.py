import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RetainedSeedComparisonTests(unittest.TestCase):
    def test_bounded_same_input_and_strict_receipts(self):
        s=(ROOT/'probes/retained-reference-seeds/Diagnostic.swift').read_text()
        self.assertIn('for seed:UInt64 in [0,1,347]',s)
        self.assertIn('F5ReferenceEngine(steps:32,seed:seed)',s)
        self.assertIn('preserveIncomplete:true',s)
        self.assertIn('SpeechRendering.render(source:raw,destination:dest,controls:SpeechControls())',s)
        self.assertIn('rawOutputSHA256:try digest(raw)',s)
        self.assertIn('wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash',s)
        self.assertIn('accepted:false,error:',s)
        self.assertIn('try encoder.encode(attempts)',s)
        self.assertNotIn('trim',s[s.index('@main'):])
    def test_readonly_pinned_original_and_no_production_write(self):
        w=yaml.safe_load((ROOT/'.github/workflows/retained-reference-seeds.yml').read_text())
        self.assertEqual(w['permissions'],{'contents':'read','actions':'read'})
        self.assertEqual(w['jobs']['actual-local-pipeline']['timeout-minutes'],50)
        s='\n'.join(x.get('run','') for x in w['jobs']['actual-local-pipeline']['steps'])
        self.assertIn('b3623b6847223e0c0704aa60a896b746d733b141152478534200fcfeb19e6779',s)
        self.assertIn('(deny network*)',s)
        self.assertIn('original=pathlib.Path(\'probes/native-local-studio/Diagnostic.swift\')',s)
        self.assertIn('Comparison evidence complete; success here does not assert all generated speech passed',s)
