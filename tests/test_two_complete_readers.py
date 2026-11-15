import importlib.util,pathlib,tempfile,unittest,io,wave,json,hashlib,copy
ROOT=pathlib.Path(__file__).resolve().parents[1]
def module(name):
 s=importlib.util.spec_from_file_location(name,ROOT/'probes/two-complete-readers'/f'{name}.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class TwoReaderTests(unittest.TestCase):
 def test_compose_preserves_each_pcm_and_exact_silence(self):
  m=module('prepare')
  def wav(value,frames):
   b=io.BytesIO()
   with wave.open(b,'wb') as w:w.setparams((1,2,16000,0,'NONE','not compressed'));w.writeframes(value*frames)
   return b.getvalue()
  a,b=wav(b'\x01\x00',16000),wav(b'\x02\x00',32000)
  out,t=m.compose([a,b])
  with wave.open(io.BytesIO(out)) as w:self.assertEqual(w.readframes(w.getnframes()),b'\x01\x00'*16000+b'\0'*64000+b'\x02\x00'*32000)
  self.assertEqual(t,[dict(start=0,end=1),dict(start=3,end=5)])
 def test_two_unique_source_intervals_and_all_new_speech_are_required(self):
  m=module('check')
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);work=p/'work';folder=work/'Jobs/job';folder.mkdir(parents=True)
   h=lambda b:hashlib.sha256(b).hexdigest()
   source=b'source';(p/'complete-source.wav').write_bytes(source);(folder/'source.wav').write_bytes(source)
   fixture=dict(audioSHA256=h(source),timeline=[dict(start=0,end=10),dict(start=12,end=22)])
   report=dict(fixtureSHA256=h(source),sourceRetainedSHA256=h(source),importedIDs=['a','b'],resumeCompleted=True,cancellationRetainedSource=True,freshStoreReloadPreservedIDs=True,priorProfilePreserved=True,newSpeeches=[])
   for i,id in enumerate(['a','b']):
    ref=('ref'+id).encode();pre=('pre'+id).encode();speech=('speech'+id).encode();(folder/f'reference-{id}.wav').write_bytes(ref);(folder/f'preview-{id}.wav').write_bytes(pre);(work/f'{id}.wav').write_bytes(speech);(work/f'{id}.json').write_text(json.dumps(dict(inputSHA256=h(speech),transcriptSHA256=h(b'Please close the window and bring the notebook.'))))
    receipt=dict(id=id,sourceSHA256=h(source),start=i*12+1,end=i*12+5,events=[dict(outcome='saved',voiceID=id,referenceSHA256=h(ref),previewSHA256=h(pre))]);(folder/f'candidate-{id}.json').write_text(json.dumps(receipt));report['newSpeeches'].append(dict(voiceID=id,referenceSHA256=h(ref),newSpeechSHA256=h(speech),newSpeechWordErrorRate=0,file=f'{id}.wav',asrFile=f'{id}.json',transcript='Please close the window and bring the notebook.'))
   m.verify(p,fixture,report)
   for mutation in ['oneID','duplicateSpeechID','wrongRef','wrongOutput','failedWER','notRetained','sameSourceInterval','wrongTranscript']:
    bad=copy.deepcopy(report)
    if mutation=='oneID':bad['importedIDs']=['a']
    elif mutation=='duplicateSpeechID':bad['newSpeeches'][1]['voiceID']='a'
    elif mutation=='wrongRef':bad['newSpeeches'][1]['referenceSHA256']='0'*64
    elif mutation=='wrongOutput':bad['newSpeeches'][1]['newSpeechSHA256']='0'*64
    elif mutation=='failedWER':bad['newSpeeches'][1]['newSpeechWordErrorRate']=.2
    elif mutation=='wrongTranscript':bad['newSpeeches'][1]['transcript']='wrong transcript'
    elif mutation=='notRetained':bad['cancellationRetainedSource']=False
    else:
     f=folder/'candidate-b.json';r=json.loads(f.read_text());r.update(start=2,end=6);f.write_text(json.dumps(r))
    with self.subTest(mutation=mutation),self.assertRaises((AssertionError,ValueError)):m.verify(p,fixture,bad)
 def test_harness_keeps_real_coordinator_and_verifies_every_imported_id(self):
  s=(ROOT/'probes/two-complete-readers/Diagnostic.swift').read_text()
  for code in ['let studio=LocalVideoStudio(', 'studio.start(fixture,authorized:true', 'studio.resume(library:library','guard expected.count == 2','for voiceID in expected.sorted()', 'reloaded.selectedID=voiceID', 'reloaded.outputCharacterID==reloaded.selectedID', 'guard wer<=0.1', 'newSpeeches:newSpeeches', 'transcript:words']:
   self.assertIn(code,s)
  self.assertNotIn('expected.sorted()[0]',s)
  self.assertNotIn('outputReferenceHash!',s)
