import hashlib,pathlib,shutil,struct,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class DiskVectorTests(unittest.TestCase):
 def test_snapshot_integrity_isolation_and_rejections(self):
  self.assertIsNotNone(shutil.which('swiftc'))
  with tempfile.TemporaryDirectory() as folder:
   root=pathlib.Path(folder);(root/'cache').mkdir()
   data=b''.join(struct.pack('<f',1+i/1000) for i in range(8*768))
   for harness in ('RVCDiskVectorChecks','RVCDiskVectorRejectChecks'):
    source=root/'input.f32';source.write_bytes(data);binary=root/harness
    subprocess.run(['swiftc','-O',str(ROOT/'VoiceMatrix/RVCDiskVectorBank.swift'),str(ROOT/'VoiceMatrix/RVCNativeRetrieval.swift'),str(ROOT/('tests/native/'+harness+'.swift')),'-o',str(binary)],check=True,timeout=60)
    args=[str(source),str(root/'cache'),'8',hashlib.sha256(data).hexdigest()] if harness=='RVCDiskVectorChecks' else [str(root)]
    subprocess.run([str(binary),*args],check=True,timeout=30)
