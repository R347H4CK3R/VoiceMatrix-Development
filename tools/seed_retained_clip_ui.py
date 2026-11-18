"""Seed/read evidence in an owned CI simulator; never generates speech or runs separation."""
import argparse,hashlib,json,struct
from pathlib import Path
VALID='D6111111-1111-4111-8111-111111111111'
CORRUPT='D6222222-2222-4222-8222-222222222222'
def sha(data):return hashlib.sha256(data).hexdigest()
def inventory(root):return {str(p.relative_to(root)):sha(p.read_bytes()) for p in sorted(root.rglob('*')) if p.is_file()} if root.exists() else {}
def source_wave(value=.125):
    pcm=struct.pack('<ff',value,-value)*(44100*6)
    return b'RIFF'+struct.pack('<I',36+len(pcm))+b'WAVEfmt '+struct.pack('<IHHIIHH',16,3,2,44100,352800,8,32)+b'data'+struct.pack('<I',len(pcm))+pcm
def roots(container):
    base=container/'Library/Application Support'
    return base/'LocalVideoStudio',base/'VocalSeparation'
def seed(container):
    jobs,separation=roots(container);jobs.mkdir(parents=True,exist_ok=True)
    for identifier,date in [(VALID,900000010),(CORRUPT,900000000)]:
        folder=jobs/identifier.lower();folder.mkdir()
        data=source_wave();actual=data if identifier==VALID else source_wave(.25)
        with (folder/'source.wav').open('xb') as f:f.write(actual)
        job=dict(id=identifier,created=date,updated=date,stage='Synthetic retained clip fixture',message='Synthetic retained source. No processing started.',sourceFile='source.wav',sourceSHA256=sha(data),completed=True,events=[])
        with (folder/'job.json').open('x') as f:json.dump(job,f,sort_keys=True)
    baseline=dict(jobs=inventory(jobs),clips=sorted(p.name for p in separation.glob('Clip-*')))
    with (container/'retained-clip-baseline.json').open('x') as f:json.dump(baseline,f,sort_keys=True)
def verify_clips(container):
    jobs,separation=roots(container)
    baseline=json.loads((container/'retained-clip-baseline.json').read_text())
    assert inventory(jobs)==baseline['jobs'],'Retained source, jobs or prior artifacts changed'
    added=[p for p in separation.glob('Clip-*') if p.name not in baseline['clips']]
    assert len(added)==1,'Expected one explicit successful clip; corrupt source must not publish'
    folder=added[0];assert not folder.is_symlink()
    assert {p.name for p in folder.iterdir()}=={'clip.wav','receipt.json'}
    r=json.loads((folder/'receipt.json').read_text());data=(folder/'clip.wav').read_bytes()
    assert r['sourceJobID']==VALID and r['sourceSHA256']==sha(source_wave())
    assert r['requestedStart']==1 and r['requestedSeconds']==1.5 and r['actualStart']==1
    assert r['frames']==66150 and len(data)==44+66150*8 and sha(data)==r['clipSHA256']
    assert data[44:]==struct.pack('<ff',.125,-.125)*66150,'Clip interval samples differ'
    return {str(p.relative_to(separation)) for p in folder.iterdir()}
def check(container):
    verify_clips(container)
    print('SYNTHETIC_RETAINED_CLIP_UI: exact selected interval retained; corrupt source rejected; original sources and jobs unchanged')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('mode',choices=['seed','check']);parser.add_argument('container',type=Path)
    args=parser.parse_args();{'seed':seed,'check':check}[args.mode](args.container)
