import importlib.util,pathlib,struct,tempfile,unittest,zipfile
p=pathlib.Path(__file__).resolve().parents[2]/'tools/python-runtime/runtime_inventory.py'
s=importlib.util.spec_from_file_location('inventory',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Inventory(unittest.TestCase):
 def test_reject_non_macho(self):
  with self.assertRaises(ValueError):m.arm64_slice(b'not native code')
 def test_exact_wheel_source_and_notice_bytes(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp)/'test.whl'
   with zipfile.ZipFile(p,'w') as z:z.writestr('demo/__init__.py','value=1');z.writestr('demo-1.dist-info/licenses/LICENSE','notice');z.writestr('demo-1.dist-info/RECORD','generated')
   out=m.wheel_inventory(p);self.assertEqual(out['demo/__init__.py']['sha256'],m.sha(b'value=1'));self.assertIn('demo-1.dist-info/licenses/LICENSE',out);self.assertEqual(len(out),2)
 def test_wheel_traversal_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp)/'bad.whl'
   with zipfile.ZipFile(p,'w') as z:z.writestr('../outside.py','code')
   with self.assertRaises(ValueError):m.wheel_inventory(p)

class SignedNative(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.path=pathlib.Path(__file__).resolve().parents[2]/'Vendors/Python/Python.xcframework/ios-arm64/lib-arm64/python3.13/lib-dynload/_ssl.cpython-313-iphoneos.so'
  if not cls.path.is_file():raise AssertionError('Required SDK fixture missing')
  cls.original=cls.path.read_bytes()
 def synthetic_signed(self):
  b=bytearray(self.original);count,extent=struct.unpack_from('<II',b,16);pos=32;link=None
  for _ in range(count):
   cmd,size=struct.unpack_from('<II',b,pos)
   if cmd==0x19 and b[pos+8:pos+24].startswith(b'__LINKEDIT\0'):link=pos
   pos+=size
  self.assertIsNotNone(link);self.assertFalse(any(b[32+extent:32+extent+16]))
  signature=b'test signature opaque bytes';padding=(-len(b))%16;sigoff=len(b)+padding
  b+=b'\0'*padding+signature
  struct.pack_into('<II',b,16,count+1,extent+16);struct.pack_into('<IIII',b,32+extent,0x1d,16,sigoff,len(signature))
  fileoff=struct.unpack_from('<Q',b,link+40)[0];size=len(b)-fileoff
  struct.pack_into('<Q',b,link+48,size);struct.pack_into('<Q',b,link+32,(size+4095)//4096*4096)
  return bytes(b)
 def test_signing_only_changes_allowed(self):
  self.assertEqual(m.verify_signed_native(self.original,self.synthetic_signed())['canonicalUnsignedSHA256'],m.sha(self.original))
 def test_export_or_other_linkedit_bytes_cannot_change(self):
  b=bytearray(self.synthetic_signed());b[len(self.original)-20]^=1
  with self.assertRaises(ValueError):m.verify_signed_native(self.original,bytes(b))
 def test_header_and_load_command_changes_rejected(self):
  for offset in (24,32+12):
   b=bytearray(self.synthetic_signed());b[offset]^=1
   with self.assertRaises(ValueError):m.verify_signed_native(self.original,bytes(b))
 @unittest.skipUnless(__import__('sys').platform=='darwin','Real Apple codesign requires native gate')
 def test_actual_apple_adhoc_signature_preserves_exact_native_identity(self):
  import subprocess
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp)/'runtime.dylib';p.write_bytes(self.original)
   subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(p)],check=True,capture_output=True)
   subprocess.run(['codesign','--verify','--strict',str(p)],check=True,capture_output=True)
   m.verify_signed_native(self.original,p.read_bytes())
