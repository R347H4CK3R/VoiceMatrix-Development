"""Verify a clean, complete source-vendored FluidAudio package, not a patched checkout."""
import hashlib,json,pathlib,re,stat,os,subprocess
REVISION='ee78635d23d52379117554ba72358b65a0612447'
TREE='2234ed3bb9af2f02d187dbd4c35e51f9eef18f44'
MODIFIED={
 'Sources/FluidAudio/Diarizer/Offline/Utils/OfflineReconstruction.swift':'d5b9f2532ecb3c5d40cb621f83ea2768a5cab56d6817c9123dc987b67b6d2c54',
 'Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift':'db5cbe9fa368dce0524c50f9610bf848fc253e108ce99eaf702a66755f4000f7'}
ADDED={'Tests/FluidAudioTests/Diarizer/Offline/EOFTimelineTests.swift','NOTICE-VoiceMatrix.txt'}
def sha(data):return hashlib.sha256(data).hexdigest()
def git_hash(kind,data):return hashlib.sha1(kind.encode()+b' '+str(len(data)).encode()+b'\0'+data).hexdigest()
def check_manifest(m):
 if m.get('schemaVersion')!=1 or m.get('revision')!=REVISION or m.get('upstreamTree')!=TREE or m.get('upstream')!='https://github.com/FluidInference/FluidAudio':raise ValueError('Unexpected vendored upstream identity')
 tree={};added=set()
 for name,info in m['files'].items():
  p=pathlib.PurePosixPath(name)
  if p.is_absolute() or '..' in p.parts or '\\' in name or p.as_posix()!=name or info['mode'] not in ('100644','100755') or not re.fullmatch('[a-f0-9]{64}',info['sha256']):raise ValueError('Unsafe inventory entry')
  blob=info['upstreamBlob']
  if blob is None:added.add(name);continue
  if not re.fullmatch('[a-f0-9]{40}',blob):raise ValueError('Invalid upstream blob')
  node=tree
  for part in p.parts[:-1]:node=node.setdefault(part,{})
  node[p.name]=(info['mode'],blob)
 if added!=ADDED:raise ValueError('Unexpected additions')
 for name,h in MODIFIED.items():
  if m['files'][name]['sha256']!=h:raise ValueError('Unexpected patch bytes')
 def treehash(node):
  raw=b''
  for name,value in sorted(node.items(),key=lambda x:(x[0]+('/' if isinstance(x[1],dict) else '')).encode()):
   mode,oid=('40000',treehash(value)) if isinstance(value,dict) else value
   raw+=mode.encode()+b' '+name.encode()+b'\0'+bytes.fromhex(oid)
  return git_hash('tree',raw)
 if treehash(tree)!=TREE:raise ValueError('Upstream tree proof differs')
def verify_modes(root,files,platform=None):
 root=pathlib.Path(root)
 if (os.name if platform is None else platform)=='nt':
  # NTFS does not expose POSIX executable bits. Require the exact Git index modes,
  # not a synthetic chmod/stat result; content hashes are independently checked.
  try: raw=subprocess.check_output(['git','-C',str(root),'ls-files','--stage','-z','--','Vendors/FluidAudio'])
  except subprocess.CalledProcessError as e:raise ValueError('Cannot verify vendor Git modes') from e
  modes={}
  for row in raw.split(b'\0'):
   if not row:continue
   header,name=row.split(b'\t');mode,oid,stage=header.decode().split();name=name.decode()
   prefix='Vendors/FluidAudio/'
   if not name.startswith(prefix) or stage!='0' or name[len(prefix):] in modes:raise ValueError('Ambiguous vendor Git index')
   modes[name[len(prefix):]]=mode
  if modes!={name:info['mode'] for name,info in files.items()}:raise ValueError('Vendor Git modes differ')
 else:
  for name,info in files.items():
   if bool((root/'Vendors/FluidAudio'/name).stat().st_mode & stat.S_IXUSR)!=(info['mode']=='100755'):raise ValueError('Vendor executable mode differs')
def verify(root):
 root=pathlib.Path(root);base=root/'Vendors/FluidAudio';manifest=root/'Vendors/FluidAudio.inventory.json'
 if base.is_symlink() or manifest.is_symlink():raise ValueError('Symlinked vendor')
 raw=manifest.read_bytes();m=json.loads(raw);check_manifest(m);seen=set()
 for p in base.rglob('*'):
  if p.is_symlink():raise ValueError('Symlinked vendor source')
  if p.is_dir():continue
  name=p.relative_to(base).as_posix();seen.add(name);info=m['files'].get(name)
  if info is None or not p.is_file():raise ValueError('Unexpected vendor source')
  data=p.read_bytes()
  if sha(data)!=info['sha256']:raise ValueError('Changed vendor source: '+name)
  if name not in MODIFIED and info['upstreamBlob'] is not None and git_hash('blob',data)!=info['upstreamBlob']:raise ValueError('Upstream bytes differ: '+name)
 if seen!=set(m['files']):raise ValueError('Missing vendor source')
 verify_modes(root,m['files'])
 return dict(schemaVersion=1,upstream=m['upstream'],revision=REVISION,upstreamTree=TREE,inventorySHA256=sha(raw),fileCount=len(seen),modified=MODIFIED,added=sorted(ADDED))
def notices(root):
 root=pathlib.Path(root);verify(root);base=root/'Vendors/FluidAudio'
 paths=[x.relative_to(base).as_posix() for x in base.rglob('*') if x.is_file() and (
  'ThirdPartyLicenses' in x.relative_to(base).parts or re.search(r'license|licence|notice|copying|copyright',x.name,re.I))]
 result={'fluid-audio-vendored/'+name:(base/name).read_bytes() for name in paths}
 result['fluid-audio-vendored/inventory.json']=(root/'Vendors/FluidAudio.inventory.json').read_bytes()
 return result
if __name__=='__main__':print(json.dumps(verify(pathlib.Path(__file__).resolve().parents[1]),indent=2))

def check_resolved(path):
 for pin in json.loads(pathlib.Path(path).read_text()).get('pins',[]):
  if pin.get('identity','').casefold()=='fluidaudio':raise ValueError('Unexpected remote FluidAudio pin; require verified local package')
