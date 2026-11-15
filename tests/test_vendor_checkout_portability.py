import pathlib,tempfile,unittest,subprocess
from unittest import mock
from tools import vendored_fluid as v
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CheckoutPortability(unittest.TestCase):
 def test_nt_modes_are_strict_git_index_modes(self):
  files={'Scripts/tool.sh':{'mode':'100755'}}
  valid=b'100755 '+b'a'*40+b' 0\tVendors/FluidAudio/Scripts/tool.sh\0'
  with mock.patch.object(v.subprocess,'check_output',return_value=valid):v.verify_modes(ROOT,files,platform='nt')
  for bad in [valid.replace(b'100755',b'100644'),valid.replace(b' 0\t',b' 1\t'),b'',valid+valid]:
   with mock.patch.object(v.subprocess,'check_output',return_value=bad),self.assertRaises(ValueError):v.verify_modes(ROOT,files,platform='nt')
 def test_checkout_with_autocrlf_keeps_exact_vendor_and_patch_bytes(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);subprocess.run(['git','init','-q',str(root)],check=True)
   files={'.gitattributes':(ROOT/'.gitattributes').read_bytes(),'Vendors/FluidAudio/.gitignore':b'one\ntwo\n','Vendors/FluidAudio/Sources/sample.swift':b'let a = 1\n','Vendors/FluidAudio/Tests/sample.wav':b'RIFF\x00\n\r\x00','Vendors/FluidAudio.inventory.json':b'{"a":1}\n','probes/diarizer-eof/fluid-eof.patch':b'--- a/a\n+++ b/a\n'}
   for n,b in files.items():p=root/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
   subprocess.run(['git','-C',str(root),'-c','core.autocrlf=false','add','-f','.'],check=True)
   out=root/'out';out.mkdir()
   subprocess.run(['git','-C',str(root),'-c','core.autocrlf=true','checkout-index','--all','--prefix='+str(out)+'/'],check=True)
   for n,b in files.items():
    if n!='.gitattributes':self.assertEqual((out/n).read_bytes(),b,n)
