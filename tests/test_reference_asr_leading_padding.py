import hashlib, importlib.util, io, pathlib, tempfile, unittest, wave, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
PATH=ROOT/'probes/reference-asr-leading-padding/prepare.py'
def module():
 spec=importlib.util.spec_from_file_location('asr_padding_prepare',PATH);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def wav(channels=1, frames=48000):
 b=io.BytesIO()
 with wave.open(b,'wb') as w:w.setparams((channels,2,24000,0,'NONE','none'));w.writeframes(b'\x01\x02' * frames * channels)
 return b.getvalue()
class PaddingTests(unittest.TestCase):
 def test_implementation_exists(self):self.assertTrue(PATH.is_file(),'Diagnostic preparer is not implemented')
 def test_preserves_samples_and_exact_padding(self):
  m=module();raw=wav()
  for name,lead,tail in m.VARIANTS:
   out,info=m.pad(raw,lead,tail)
   with wave.open(io.BytesIO(out)) as w:pcm=w.readframes(w.getnframes());self.assertEqual(w.getnframes(),48000+round((lead+tail)*24000))
   self.assertEqual(pcm,bytes(round(lead*24000)*2)+b'\x01\x02'*48000+bytes(round(tail*24000)*2))
   self.assertEqual(info['sourceSHA256'],hashlib.sha256(raw).hexdigest());self.assertEqual(info['sourceBytes'],len(raw))
   if name=='original':self.assertEqual(raw,out)
 def test_bad_audio(self):
  m=module()
  for raw in [b'not audio',wav(2),wav(frames=0)]:
   with self.assertRaises((ValueError,wave.Error,EOFError)):m.pad(raw,0.25,0)
  for lead,tail in [(-1,0),(float('nan'),0),(0,2)]:
   with self.assertRaises(ValueError):m.pad(wav(),lead,tail)
 def test_zip_rejects_traversal_wrong_hash_duplicates_and_missing(self):
  m=module()
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'a.zip'
   for names in [['../outside'],['/outside'],['a\\b'],['good','good'],['wrong']]:
    with zipfile.ZipFile(p,'w') as z:
     for n in names:z.writestr(n,b'foo')
    h=hashlib.sha256(p.read_bytes()).hexdigest()
    with self.assertRaises(ValueError):m.read_archive(p,h,{'good':hashlib.sha256(b'foo').hexdigest()})
   with zipfile.ZipFile(p,'w') as z:z.writestr('good',b'foo')
   h=hashlib.sha256(p.read_bytes()).hexdigest()
   with self.assertRaises(ValueError):m.read_archive(p,'0'*64,{'good':hashlib.sha256(b'foo').hexdigest()})
   with self.assertRaises(ValueError):m.read_archive(p,h,{'good':'0'*64})
   self.assertEqual(m.read_archive(p,h,{'good':hashlib.sha256(b'foo').hexdigest()}),{'good':b'foo'})
 def test_output_no_overwrite_and_holdouts(self):
  m=module()
  with tempfile.TemporaryDirectory() as d:
   out=pathlib.Path(d)/'matrix'; records=m.write_matrix({'exact':wav()},out)
   self.assertEqual(len(records),4)
   for r in records:self.assertEqual(hashlib.sha256((out/r['file']).read_bytes()).hexdigest(),r['sha256'])
   with self.assertRaises(FileExistsError):m.write_matrix({'exact':wav()},out)
  self.assertEqual(set(m.holdouts(ROOT)),{'conversion-source','conversion-reference'})
if __name__=='__main__':unittest.main()

class WorkflowContractTests(unittest.TestCase):
 def test_workflow_invokes_actual_cli_and_no_production_override(self):
  import yaml,shlex
  workflow=yaml.safe_load((ROOT/'.github/workflows/reference-asr-leading-padding.yml').read_text())
  lines=[line.strip() for step in workflow['jobs']['diagnose']['steps'] for line in step.get('run','').splitlines()]
  self.assertIn('python3 -m pip install -r tests/requirements-native.txt',lines)
  command=next(line for line in lines if line.startswith('python3 probes/reference-asr-leading-padding/prepare.py'))
  self.assertEqual(shlex.split(command),['python3','probes/reference-asr-leading-padding/prepare.py','retained.zip','padding-evidence'])
  probe=(ROOT/'probes/reference-asr-leading-padding/Sources/Probe/Probe.swift').read_text()
  self.assertIn('recognizer.transcribe(file)',probe)
  self.assertNotIn('transcribe(file,',probe)
  self.assertIn('NOT a repaired recognizer',probe)
