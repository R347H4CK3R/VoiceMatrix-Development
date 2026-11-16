import copy,hashlib,importlib.util,json,pathlib,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];PATH=ROOT/'probes/reference-context-receipts.py'
def module():
 s=importlib.util.spec_from_file_location('context_receipts',PATH);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class ReceiptTests(unittest.TestCase):
 def test_exists(self):self.assertTrue(PATH.is_file(),'Receipt gate missing')
 def fixture(self,root):
  folder=root/'work/Jobs/job';folder.mkdir(parents=True);rows=[]
  def write(p,data):p.write_text(json.dumps(data))
  def receipt(sha,context):return dict(schemaVersion=2,modelRevision='7dd20fe6b1797d35f5e3307e8b1732d9a178edfe',inputSHA256=sha,transcriptSHA256='b'*64,tokenCount=8,meanTokenConfidence=.8,referenceLeadingSeconds=context)
  for i in range(2):
   ref=b'reference'+bytes([i]);preview=b'preview'+bytes([i]);final=b'final'+bytes([i]);h=lambda b:hashlib.sha256(b).hexdigest();identity=f'candidate-{i}'
   (folder/f'reference-{identity}.wav').write_bytes(ref);(folder/f'preview-{identity}.wav').write_bytes(preview);(root/'work'/f'final-{i}.wav').write_bytes(final)
   write(folder/f'candidate-{identity}.json',dict(id=identity,events=[dict(outcome='saved',voiceID=f'voice-{i}',referenceSHA256=h(ref),previewSHA256=h(preview))]))
   write(folder/f'transcription-evidence-{identity}.json',receipt(h(ref),.25));write(folder/f'preview-asr-evidence-{identity}.json',receipt(h(preview),None));write(root/'work'/f'final-{i}.json',receipt(h(final),None))
   rows.append(dict(voiceID=f'voice-{i}',file=f'final-{i}.wav',asrFile=f'final-{i}.json',newSpeechSHA256=h(final),referenceSHA256=h(ref)))
  return dict(importedIDs=['voice-0','voice-1'],newSpeeches=rows),folder
 def test_bound_positive(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);report,folder=self.fixture(root);self.assertEqual(module().verify_receipts(root,report)['referenceReceipts'],2)
 def test_wrong_context_hash_missing_and_incomplete_receipts(self):
  for prefix,key,value in [('transcription-evidence-','referenceLeadingSeconds',None),('transcription-evidence-','recoveryTailSeconds',.16),('preview-asr-evidence-','referenceLeadingSeconds',.25),('transcription-evidence-','inputSHA256','0'*64),('transcription-evidence-','tokenCount',0),('transcription-evidence-','meanTokenConfidence',float('nan'))]:
   with self.subTest(key=key,value=value),tempfile.TemporaryDirectory() as d:
    root=pathlib.Path(d);report,folder=self.fixture(root);p=folder/(prefix+'candidate-0.json');o=json.loads(p.read_text());o[key]=value;p.write_text(json.dumps(o))
    with self.assertRaises(ValueError):module().verify_receipts(root,report)
  for action in ['missing','final-context','missing-field','duplicate']:
   with self.subTest(action=action),tempfile.TemporaryDirectory() as d:
    root=pathlib.Path(d);report,folder=self.fixture(root);p=folder/'transcription-evidence-candidate-0.json'
    if action=='missing':p.unlink()
    elif action=='missing-field':p.write_text('{}')
    elif action=='duplicate':report['newSpeeches'][1]=report['newSpeeches'][0]
    else:
     p=root/'work/final-0.json';o=json.loads(p.read_text());o['referenceLeadingSeconds']=.25;p.write_text(json.dumps(o))
    with self.assertRaises((ValueError,FileNotFoundError)):module().verify_receipts(root,report)
if __name__=='__main__':unittest.main()
