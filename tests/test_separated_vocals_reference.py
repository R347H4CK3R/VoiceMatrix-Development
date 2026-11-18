import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class HandoffSurfaceTests(unittest.TestCase):
 def test_explicit_navigation_and_no_auto_authorization(self):
  separation=(ROOT/'VoiceMatrix/VocalSeparationView.swift').read_text()
  view=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  self.assertIn('LocalVideoStudioView(initialSeparatedVocals: result)',separation)
  self.assertIn('Use vocals for speaker references',separation)
  self.assertIn('Separation is not identity verification',view)
  self.assertIn('authorized = false',view)
  self.assertIn('SeparationStore.standard.referenceInput(for: result)',view)
  self.assertIn('referenceInput: separatedInput',view)
 def test_expected_consumed_bytes_precede_commit(self):
  source=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertIn('referenceInput: SeparationStore.ReferenceInput? = nil',source)
  self.assertIn('referenceInput.validateCopied(digest: digest, bytes:',source)
  self.assertLess(source.index('referenceInput.validateCopied(digest: digest'),source.index('current?.sourceFile = destination.lastPathComponent'))

 def test_real_copy_gate_is_wired_and_selection_cannot_auto_start(self):
  source=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertIn('if let referenceInput { return try referenceInput.copyVerified(to: destination) }',source)
  view=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  task=view[view.index('guard !preparedSeparatedInput'):view.index('.onChange(of: local.current?.id)')]
  self.assertNotIn('local.start(',task)
  self.assertIn('authorized = false',task)
  self.assertIn('withTaskCancellationHandler',task)
  self.assertIn('audio.releaseProcessing(lease)',task)
  self.assertIn('try Task.checkCancellation()',task)
  self.assertIn('if separatedInput != nil { selected = nil }',view)

 def test_native_workflow_runs_actual_copy_probe_on_feature_branch(self):
  text=(ROOT/'.github/workflows/vocal-separation-native.yml').read_text()
  self.assertIn('feature/separated-vocals-reference',text)
  self.assertIn('tests.test_separation_store tests.test_separated_vocals_reference',text)
