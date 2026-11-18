"""Pinned Spleeter two-stem model staging. No upstream executable scripts are run."""
import argparse,hashlib,json,pathlib,shutil,tarfile,tempfile,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
URL='https://github.com/k2-fsa/sherpa-onnx/releases/download/source-separation-models/sherpa-onnx-spleeter-2stems.tar.bz2'
ARCHIVE_BYTES=74682545
ARCHIVE_SHA='e26401d9c1801f43c0229731d78d32c2e80085e3aceedeb25f29d2de5fa68ca2'
MODELS={
 'vocals.onnx':(39318336,'bdc16ab6bf6117ddd4842c19e80e40e2be188fc555295064d424616b0224ac97'),
 'accompaniment.onnx':(39318343,'671ace17acd3720674a2bc14de32ac6292453dec20d9eb0ba4255d4ad8e3d8c0'),
}
PROVENANCE={'model':'Deezer Spleeter 2 stems, float32 ONNX conversion','modelLicense':'MIT','modelLicenseEvidence':'https://doi.org/10.21105/joss.02154',
 'upstream':'https://github.com/deezer/spleeter','conversion':'https://github.com/k2-fsa/sherpa-onnx/tree/a8cd5f3bc9490a9a58aa319cf0d5b60b6cd9e642/scripts/spleeter',
 'conversionLicense':'Apache-2.0','archiveURL':URL,'archiveSHA256':ARCHIVE_SHA,'archiveBytes':ARCHIVE_BYTES,
 'sampleRate':44100,'maximumSeconds':10,'metadataNotice':'Published graph metadata says 41000; published Python and C++ inference both use 44100. This pack pins the 44100 reference contract.',
 'models':{k:{'bytes':v[0],'sha256':v[1]} for k,v in MODELS.items()},'scope':'Experimental band-limited vocals/accompaniment separation; no quality or device-performance guarantee.'}

def check(path,size,sha):
 if path.is_symlink() or not path.is_file() or path.stat().st_size!=size:raise ValueError('Pinned file size/type mismatch')
 with path.open('rb') as f:
  if hashlib.file_digest(f,'sha256').hexdigest()!=sha:raise ValueError('Pinned file hash mismatch')

def validate(folder):
 if folder.is_symlink() or not folder.is_dir():raise ValueError('Unsafe model folder')
 for name,(size,sha) in MODELS.items():check(folder/name,size,sha)

def prepare(destination,archive=None):
 destination=pathlib.Path(destination)
 if destination.exists() or destination.is_symlink():validate(destination);return destination
 destination.parent.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='.separation-staging-',dir=destination.parent) as td:
  temp=pathlib.Path(td)
  if archive is None:
   archive=temp/'models.tar.bz2';deadline=time.monotonic()+180
   with urllib.request.urlopen(URL,timeout=30) as source,archive.open('xb') as output:
    total=0
    while block:=source.read(1024*1024):
     total+=len(block)
     if total>ARCHIVE_BYTES or time.monotonic()>deadline:raise ValueError('Model download exceeds bounds')
     output.write(block)
  else:archive=pathlib.Path(archive)
  check(archive,ARCHIVE_BYTES,ARCHIVE_SHA)
  staged=temp/'Separation';staged.mkdir()
  with tarfile.open(archive,'r:bz2') as bundle:
   members=bundle.getmembers();expected={'sherpa-onnx-spleeter-2stems/'+name for name in MODELS}
   files=[m for m in members if m.isfile()]
   if len(members)!=3 or {m.name for m in files}!=expected or len(files)!=2:raise ValueError('Unexpected model archive inventory')
   if any(not (m.isfile() or (m.isdir() and m.name=='sherpa-onnx-spleeter-2stems')) for m in members):raise ValueError('Unsafe archive member')
   for member in files:
    name=pathlib.PurePosixPath(member.name).name
    if member.size!=MODELS[name][0]:raise ValueError('Model member size mismatch')
    with bundle.extractfile(member) as source,(staged/name).open('xb') as output:
     shutil.copyfileobj(source,output,1024*1024)
  validate(staged)
  (staged/'manifest.json').write_text(json.dumps(PROVENANCE,indent=2)+'\n')
  shutil.copyfile(ROOT/'LICENSES/Spleeter-MIT.txt',staged/'LICENSES.txt')
  # CI creates this folder in its own workspace. Never replace an existing pack.
  if destination.exists() or destination.is_symlink():raise ValueError('Destination appeared during preparation')
  staged.rename(destination)
 return destination

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=pathlib.Path,default=ROOT/'VoiceMatrix/Resources/Separation');p.add_argument('--archive',type=pathlib.Path)
 a=p.parse_args();print(prepare(a.output,a.archive))
