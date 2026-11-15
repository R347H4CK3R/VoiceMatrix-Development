"""One-time deterministic source materialization. Does not push or alter existing refs."""
import pathlib,json,subprocess,shutil,sys
ROOT=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from tools.vendored_fluid import verify,check_manifest,git_hash
m=json.loads((ROOT/'Vendors/FluidAudio.inventory.json').read_text());check_manifest(m)
dst=ROOT/'Vendors/FluidAudio'
if dst.exists():raise SystemExit('Refuse existing vendor directory')
upstream=pathlib.Path(sys.argv[1]).resolve()
if subprocess.check_output(['git','-C',str(upstream),'rev-parse','HEAD'],text=True).strip()!=m['revision']:raise SystemExit('Wrong upstream commit')
if subprocess.check_output(['git','-C',str(upstream),'rev-parse','HEAD^{tree}'],text=True).strip()!=m['upstreamTree']:raise SystemExit('Wrong upstream tree')
for name,info in m['files'].items():
 if info['upstreamBlob'] is None:continue
 data=subprocess.check_output(['git','-C',str(upstream),'cat-file','blob',info['upstreamBlob']]);p=dst/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);p.chmod(int(info['mode'],8)&0o777)
# Already independently reviewed, exact source-byte patch; no compiler flags or guard changes.
subprocess.run(['git','apply','--directory=Vendors/FluidAudio',str(ROOT/'probes/diarizer-eof/fluid-eof.patch')],cwd=ROOT,check=True)
for source,target in [('probes/diarizer-eof/EOFTimelineTests.swift','Tests/FluidAudioTests/Diarizer/Offline/EOFTimelineTests.swift'),('probes/vendored-fluid-bootstrap/NOTICE-VoiceMatrix.txt','NOTICE-VoiceMatrix.txt')]:
 p=dst/target;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/source,p);p.chmod(0o644)
proof=verify(ROOT)
paths=['Vendors/FluidAudio/'+name for name in m['files']]
subprocess.run(['git','add','-f','--',*paths],cwd=ROOT,check=True)
staged=set(subprocess.check_output(['git','diff','--cached','--name-only','-z'],cwd=ROOT).decode().rstrip('\0').split('\0'))
if staged!=set(paths):raise SystemExit('Unexpected staged paths')
for row in subprocess.check_output(['git','ls-files','-s','-z','--','Vendors/FluidAudio'],cwd=ROOT).split(b'\0'):
 if not row:continue
 info,name=row.split(b'\t');mode,oid,stage=info.decode().split();relative=name.decode().removeprefix('Vendors/FluidAudio/');expected=m['files'][relative]
 if stage!='0' or mode!=expected['mode'] or oid!=git_hash('blob',(dst/relative).read_bytes()):raise SystemExit('Index source mismatch')
subprocess.run(['git','-c','user.name=VoiceMatrix build','-c','user.email=51473529+R347H4CK3R@users.noreply.github.com','commit','-m','vendor: pin complete FluidAudio source with bounded EOF reconstruction'],cwd=ROOT,check=True)
proof['commit']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip();proof['committedVendorTree']=subprocess.check_output(['git','rev-parse','HEAD:Vendors/FluidAudio'],cwd=ROOT,text=True).strip()
if proof['committedVendorTree']!='a81cf0a7d3f92355a17b03fdc5389e85bcd1c225':raise SystemExit('Unexpected committed vendor tree')
actual=set(subprocess.check_output(['git','ls-tree','-r','--name-only','HEAD','--','Vendors/FluidAudio'],cwd=ROOT,text=True).splitlines())
if actual!=set(paths):raise SystemExit('Committed vendor inventory differs')
if subprocess.check_output(['git','status','--porcelain','--','Vendors'],cwd=ROOT,text=True).strip():raise SystemExit('Vendor source not clean after commit')
(ROOT/'materialization-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
