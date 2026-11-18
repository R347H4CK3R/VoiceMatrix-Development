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
 def test_every_explicit_coordinator_target_compiles_real_separation_dependencies(self):
  import yaml
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  checked=[]
  for name,target in project['targets'].items():
   paths=[s['path'] for s in target.get('sources',[]) if isinstance(s,dict)]
   if 'VoiceMatrix/LocalVideoStudio.swift' in paths:
    checked.append(name)
    for dependency in ['SeparationStore','VocalSeparationAssets','RetainedMediaReader']:
     self.assertIn('VoiceMatrix/'+dependency+'.swift',paths,name)
  self.assertIn('LocalStudioDiagnostic',checked)
 def test_native_probe_reports_safe_stage_and_receipt_comparisons(self):
  probe=(ROOT/'probes/separation-store/main.swift').read_text()
  for marker in ['SEPARATION_STORE_STAGE:', 'directoryURL', 'directoryPath', 'SEPARATION_STORE_DATE_DELTA=', 'FAIL separation store probe stage=', 'exit(1)']:
   self.assertIn(marker,probe)
