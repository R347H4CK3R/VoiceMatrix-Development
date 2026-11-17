import hashlib,json,pathlib,subprocess,sys,zipfile
SOURCE='c6b140e036b144a57ec7f190865b40a11bd48175'
IPA='VoiceMatrix-0.4.13-build16.ipa'
def digest(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def extract_python_runtime(ipa,dest):
 # Select only actual IPA resources needed by the independent runtime inspector.
 # Validate every archive path, including entries not selected for extraction.
 prefix='Payload/VoiceMatrix.app/'
 with zipfile.ZipFile(ipa) as archive:
  names=archive.namelist()
  assert len(names)==len(set(names)) and sum(i.file_size for i in archive.infolist())<5_000_000_000
  for entry in archive.infolist():
   path=pathlib.PurePosixPath(entry.filename)
   assert not path.is_absolute() and '..' not in path.parts and '\\' not in entry.filename and ':' not in entry.filename
   assert (entry.external_attr>>16)&0o170000!=0o120000
   assert not entry.filename.endswith(('.pyc','.pyo'))
   if not entry.filename.startswith(prefix):continue
   relative=entry.filename[len(prefix):]
   if relative=='Info.plist' or any(relative.startswith(part+'/') for part in ('Frameworks','python','app_packages','PythonRuntimeNotices')):
    archive.extract(entry,dest)
 return dest/'Payload/VoiceMatrix.app'

def validate_python_runtime(root,candidate):
 # Re-fetch/reverify pinned SDK and wheel archives independently of the build's proof.
 subprocess.run([sys.executable,str(candidate/'tools/python-runtime/prepare_app_python.py')],check=True,cwd=candidate)
 app=extract_python_runtime(root/IPA,root/'python-reinspection')
 output=root/'python-runtime-reinspection.json'
 subprocess.run([sys.executable,str(candidate/'tools/python-runtime/verify_python_bundle.py'),str(app),'--json-out',str(output)],check=True,cwd=candidate)
 actual=json.loads(output.read_text());expected=json.loads((root/'python-runtime-inspection.json').read_text())
 assert actual==expected,'Packaged Python runtime differs from independent pinned-source inspection'
 assert actual['version']=='0.4.13' and actual['build']=='16' and len(actual['native'])==69 and len(actual['wheels'])==3
 return dict(sourceCommit=SOURCE,inspectionSHA256=digest(output),nativeBinaries=69,wheels=3,independentPinnedArchiveVerification=True)

