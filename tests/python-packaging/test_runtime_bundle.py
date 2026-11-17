import importlib.util,pathlib,plistlib,shutil,sys,tarfile,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/python-runtime'))
import verify_python_bundle as verifier
class RuntimeBundle(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.app=pathlib.Path(cls.tmp.name)/'VoiceMatrix.app';cls.app.mkdir()
  (cls.app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.voicematrix.app','CFBundleShortVersionString':'0.4.12','CFBundleVersion':'15'}))
  def write(path,data):
   p=cls.app/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
  archive=ROOT/'Vendors/Python/Python-3.13-iOS-support.b18.tar.gz'
  if not archive.is_file():raise AssertionError('Required pinned SDK fixture not prepared')
  with tarfile.open(archive) as tf:
   template=plistlib.loads(tf.extractfile('Python.xcframework/build/iOS-dylib-Info-template.plist').read())
   write('Frameworks/Python.framework/Info.plist',tf.extractfile('Python.xcframework/ios-arm64/Python.framework/Info.plist').read())
   for member in tf.getmembers():
    if not member.isfile():continue
    name=member.name
    if name=='Python.xcframework/ios-arm64/Python.framework/Python':write('Frameworks/Python.framework/Python',tf.extractfile(member).read());continue
    prefix=next((p for p in ('Python.xcframework/lib/','Python.xcframework/ios-arm64/lib-arm64/') if name.startswith(p)),None)
    if not prefix:continue
    relative='python/lib/'+name[len(prefix):];data=tf.extractfile(member).read()
    if relative.startswith('python/lib/python3.13/test/'):continue
    if relative.endswith('.so'):
     module=pathlib.PurePosixPath(relative).name.split('.')[0];target=f'Frameworks/{module}.framework/{module}'
     write(target,data);write(relative[:-3]+'.fwork',(target+'\n').encode())
     write(f'Frameworks/{module}.framework/{module}.origin',(relative[:-3]+'.fwork\n').encode())
     metadata=dict(template,CFBundleExecutable=module,CFBundleIdentifier=('com.voicematrix.app.'+module).replace('_','-'))
     write(f'Frameworks/{module}.framework/Info.plist',plistlib.dumps(metadata))
    elif relative.endswith('.xcprivacy'):
     module=pathlib.PurePosixPath(relative).stem;write(f'Frameworks/{module}.framework/PrivacyInfo.xcprivacy',data)
    elif '__pycache__' not in relative and not relative.endswith(('.pyc','.dylib')):write(relative,data)
  shutil.copytree(ROOT/'.python-runtime/app_packages',cls.app/'app_packages')
  shutil.copytree(ROOT/'VoiceMatrix/Resources/PythonRuntimeNotices',cls.app/'PythonRuntimeNotices')
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def test_exact_pinned_runtime_emits_proof(self):
  proof=verifier.inspect(self.app);self.assertEqual(len(proof['native']),69);self.assertEqual(len(proof['wheels']),3);self.assertGreater(len(proof['resources']),1000)
 def test_changed_python_code_fails(self):
  p=self.app/'app_packages/yt_dlp/__init__.py';original=p.read_bytes()
  try:
   p.write_bytes(original+b'\n# changed\n')
   with self.assertRaises((AssertionError,ValueError)):verifier.inspect(self.app)
  finally:p.write_bytes(original)
 def test_changed_native_linkage_fails(self):
  p=self.app/'Frameworks/_ssl.framework/_ssl';original=p.read_bytes();changed=original.replace(b'@rpath/Python.framework/Python',b'@rpath/Python.framework/Pythoo',1)
  self.assertNotEqual(original,changed)
  try:
   p.write_bytes(changed)
   with self.assertRaises((AssertionError,ValueError)):verifier.inspect(self.app)
  finally:p.write_bytes(original)
 def test_extra_python_code_fails(self):
  p=self.app/'app_packages/injected.py'
  try:
   p.write_text('print(123)')
   with self.assertRaises((AssertionError,ValueError)):verifier.inspect(self.app)
  finally:p.unlink(missing_ok=True)

 def test_extra_stdlib_sitecustomize_fails(self):
  p=self.app/'python/lib/sitecustomize.py'
  try:
   p.write_text('print(123)')
   with self.assertRaises(AssertionError):verifier.inspect(self.app)
  finally:p.unlink(missing_ok=True)
 def test_symlink_in_runtime_tree_fails_before_read(self):
  p=self.app/'python/lib/escape.py';outside=pathlib.Path(self.tmp.name)/'outside.py';outside.write_text('print(123)')
  try:
   p.symlink_to(outside)
   with self.assertRaises(AssertionError):verifier.inspect(self.app)
  finally:p.unlink(missing_ok=True);outside.unlink(missing_ok=True)
 def test_extra_native_framework_resource_fails(self):
  p=self.app/'Frameworks/_ssl.framework/injected.py'
  try:
   p.write_text('print(123)')
   with self.assertRaises(AssertionError):verifier.inspect(self.app)
  finally:p.unlink(missing_ok=True)

 def test_production_runtime_excludes_upstream_test_audio(self):
  self.assertFalse((self.app/'python/lib/python3.13/test').exists())
  forbidden={'.wav','.aiff','.aif','.mp3','.m4a','.flac','.ogg','.vmpack','.pth'}
  self.assertFalse([p for p in (self.app/'python').rglob('*') if p.is_file() and p.suffix.lower() in forbidden])
  self.assertIn('rm -rf "$CODESIGNING_FOLDER_PATH/python/lib/python3.13/test"',(ROOT/'tools/python-runtime/install_python_runtime.sh').read_text())
 def test_reintroduced_upstream_test_fixture_rejected(self):
  p=self.app/'python/lib/python3.13/test/audiodata/pluck-pcm16.wav'
  original=p.read_bytes() if p.exists() else None
  try:
   p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'RIFF fixture')
   with self.assertRaises(AssertionError):verifier.inspect(self.app)
  finally:
   if original is None:p.unlink(missing_ok=True)
   else:p.write_bytes(original)
