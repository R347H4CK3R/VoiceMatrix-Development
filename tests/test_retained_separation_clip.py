import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RetainedClipSurfaceTests(unittest.TestCase):
 def test_explicit_retained_source_handoff_keeps_inference_manual(self):
  view=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  self.assertIn('Prepare selected clip for separation',view)
  self.assertIn('retained-clip-authorization',view)
  self.assertIn('VocalSeparationView(initialClip:',view)
  self.assertIn('audio.claimProcessing()',view)
  self.assertIn('clipWork?.cancel()',view)
  self.assertIn('scenePhase',view)
  destination=(ROOT/'VoiceMatrix/VocalSeparationView.swift').read_text()
  self.assertIn('func acceptClip(',destination)
  method=destination.split('func acceptClip(',1)[1].split('func run(',1)[0]
  self.assertNotIn('engine.separate',method)
  self.assertIn('SeparationClipHandoff.validate',method)
 def test_source_snapshot_is_bound_before_decode_and_after(self):
  source=(ROOT/'VoiceMatrix/SeparationClipHandoff.swift').read_text()
  self.assertLess(source.index('hash.finalize()'),source.index('SeparationClipExtractor.extract'))
  self.assertLess(source.index('SeparationClipExtractor.extract'),source.index('SeparationStore.digest(snapshot'))
  self.assertLess(source.index('SeparationStore.digest(snapshot'),source.index('renamex_np'))
  self.assertIn('options:.withoutOverwriting',source)
  self.assertIn('RENAME_EXCL',source)
  self.assertIn('sourceJobID:source.jobID',source)
  self.assertIn('receiptSHA256',source)
 def test_explicit_coordinator_targets_compile_new_dependencies(self):
  import yaml
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  for name,target in project['targets'].items():
   paths=[s['path'] for s in target.get('sources',[]) if isinstance(s,dict)]
   if 'VoiceMatrix/LocalVideoStudio.swift' in paths:
    for dependency in ['SeparationClipHandoff','SeparationClipExtractor','SeparationStore','VocalSeparationAssets']:
     self.assertIn('VoiceMatrix/'+dependency+'.swift',paths,name)
 def test_retained_filename_guard_accepts_real_extension_not_paths(self):
  import json,re
  text=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text().split('var retainedSeparationSource',1)[1]
  literal=re.search(r'name.range\(of:("[^"\n]+")',text).group(1)
  pattern=json.loads(literal)
  for name in ['source.wav','source.mp4','retained-audio.m4a']:
   self.assertIsNotNone(re.fullmatch(pattern,name))
  for name in ['../source.wav','dir/source.wav','source\\wav']:
   self.assertIsNone(re.fullmatch(pattern,name))

 def test_pending_clip_retries_only_admission_not_inference(self):
  source=(ROOT/'VoiceMatrix/VocalSeparationView.swift').read_text()
  self.assertIn('loadedInitialClip=studio.acceptClip(initialClip,audio:audio)',source)
  self.assertIn('acceptedClipID != initialClip?.id',source)
  self.assertIn('.onChange(of:audio.processingInUse)',source)
  method=source.split('private func loadInitialClipIfReady()',1)[1]
  self.assertNotIn('studio.run',method)
  self.assertIn('scene == .active',method)
 def test_crash_staging_bound_reserves_next_complete_copy(self):
  source=(ROOT/'VoiceMatrix/SeparationClipHandoff.swift').read_text()
  self.assertIn('1_073_741_824-541_000_000',source)
  self.assertIn('files.count<=3',source)
  self.assertIn('info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG)',source)
  self.assertLess(source.index('try admitScratch(store:store)'),source.index('let id=UUID()'))
 def test_decoder_forbids_external_media_references(self):
  source=(ROOT/'VoiceMatrix/SeparationClipExtractor.swift').read_text()
  self.assertIn('AVURLAssetReferenceRestrictionsKey',source)
  self.assertIn('AVAssetReferenceRestrictions.forbidAll.rawValue',source)
