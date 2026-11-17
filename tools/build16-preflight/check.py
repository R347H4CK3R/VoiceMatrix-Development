import hashlib,json,os,pathlib,subprocess,zipfile
SOURCE='bb4b6e2137566008143f6b17c8610880828f0750'
ARTIFACT=14338189716
DIGEST='9b3888623047da4c5f66707b45ecd588cee87ee53f7b71edd83bcf74e92b3fe3'
RUN=44095891874
REPO='R347H4CK3R/VoiceMatrix-Development'
IPA='VoiceMatrix-0.4.13-build16.ipa'
assert ARTIFACT>0 and len(DIGEST)==64
metadata=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/actions/artifacts/{ARTIFACT}']))
assert metadata['name']=='Character-test-IPA'
run=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/actions/runs/{RUN}']))
assert run['head_sha']==SOURCE and run['path']=='.github/workflows/iphone-build16.yml'
assert run['status']=='completed' and run['conclusion']=='success'
assert metadata['workflow_run']['head_sha']==SOURCE and metadata['workflow_run']['id']==RUN
assert metadata['digest']=='sha256:'+DIGEST and not metadata['expired']
with open('package.zip','wb') as f:subprocess.run(['gh','api',f'repos/{REPO}/actions/artifacts/{ARTIFACT}/zip'],stdout=f,check=True)
def digest(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
assert digest('package.zip')==DIGEST
expected={IPA,'python-runtime-inspection.json','python-runtime-inspection.log','character-inspection.json','character-ipa.sha256','source-proof.json','dependency-notices.json','assets.json','packaging-status.json','vendor-before.json','vendor-after.json'}
with zipfile.ZipFile('package.zip') as z:
 assert set(z.namelist())==expected and len(z.namelist())==len(expected) and z.testzip() is None
 z.extractall('package')
p=pathlib.Path('package'); proof=json.loads((p/'source-proof.json').read_text());assert proof['sourceCommit']==SOURCE
for name, expected_hash in proof['files'].items():
 path=pathlib.PurePosixPath(name)
 assert not path.is_absolute() and '..' not in path.parts and '\\' not in name
 assert digest(pathlib.Path(name))==expected_hash, name
fingerprint=dict(proof); fingerprint.pop('inferenceSourceFingerprint')
assert hashlib.sha256(json.dumps(fingerprint,sort_keys=True,separators=(',',':')).encode()).hexdigest()==proof['inferenceSourceFingerprint']
from tools.character_evidence import embedded_source_paths
assert {p.as_posix() for p in embedded_source_paths()} <= set(proof['files'])
from tools.character_package import inspect_ipa,PREFIX
notices=json.loads((p/'dependency-notices.json').read_text())
inspection=inspect_ipa(p/IPA,dependency_proof=notices['proof'],expected_version='0.4.13',expected_build='16')
assert inspection==json.loads((p/'character-inspection.json').read_text())
with zipfile.ZipFile(p/IPA) as z:assert json.loads(z.read(PREFIX+'VoiceMatrix-Source-Proof.json'))==proof
ipa_hash=digest(p/IPA);assert (p/'character-ipa.sha256').read_text().split()==[ipa_hash,IPA]
from runtime_preflight import validate_python_runtime
python_proof=validate_python_runtime(p.resolve(),pathlib.Path('.').resolve())
(p/'preflight.json').write_text(json.dumps(dict(sourceCommit=SOURCE,artifactID=ARTIFACT,artifactSHA256=DIGEST,ipaSHA256=ipa_hash,ipaBytes=(p/IPA).stat().st_size,pythonRuntimeProof=python_proof),indent=2))
