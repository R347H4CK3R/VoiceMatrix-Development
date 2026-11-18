"""Synthetic handoff UI evidence only, in an owned CI simulator. No model/inference claim."""
import argparse, hashlib, json, struct
from pathlib import Path
from tools.prepare_vocal_separation import MODELS

VALID='B2E33332-AE5E-423F-9B44-555555555551'
CORRUPT='B2E33332-AE5E-423F-9B44-555555555552'

def sha(data): return hashlib.sha256(data).hexdigest()
def wave(value):
    pcm=struct.pack('<ff',value,-value)*441
    return b'RIFF'+struct.pack('<I',36+len(pcm))+b'WAVEfmt '+struct.pack('<IHHIIHH',16,3,2,44100,352800,8,32)+b'data'+struct.pack('<I',len(pcm))+pcm

def inventory(root):
    if not root.exists(): return {}
    return {str(p.relative_to(root)):sha(p.read_bytes()) for p in sorted(root.rglob('*')) if p.is_file()}

def paths(container):
    support=container/'Library/Application Support'
    return support/'VocalSeparation',support/'LocalVideoStudio'

def fixture(identifier):
    vocal,backing=wave(.125),wave(.25)
    receipt=dict(id=identifier,date=800000042,inputName='UI synthetic separated vocals.wav',inputSHA256=sha(wave(.375)),
                 modelSHA256={name:meta[1] for name,meta in MODELS.items()},frames=441,gain=1,
                 vocalsSHA256=sha(vocal),accompanimentSHA256=sha(backing))
    return vocal,backing,receipt

def seed(container):
    root,jobs=paths(container);root.mkdir(parents=True,exist_ok=True)
    with (root/'UI-original.wav').open('xb') as f:f.write(wave(.375))
    for identifier in [VALID,CORRUPT]:
        folder=root/('Result-'+identifier);folder.mkdir()
        vocal,backing,receipt=fixture(identifier)
        if identifier==CORRUPT: vocal=wave(.5) # Valid WAV, wrong receipt digest.
        with (folder/('Vocals-'+identifier+'.wav')).open('xb') as f:f.write(vocal)
        with (folder/('Accompaniment-'+identifier+'.wav')).open('xb') as f:f.write(backing)
        with (folder/'receipt.json').open('x') as f:json.dump(receipt,f,sort_keys=True)
    baseline=dict(files=inventory(root),jobs=inventory(jobs))
    with (container/'separation-handoff-baseline.json').open('x') as f:json.dump(baseline,f,sort_keys=True)

def check(container,allow_retained_clips=False):
    root,jobs=paths(container)
    baseline=json.loads((container/'separation-handoff-baseline.json').read_text())
    current=inventory(root)
    for name,digest in baseline['files'].items():assert current.get(name)==digest,'Original or stem changed: '+name
    added=set(current)-set(baseline['files'])
    if allow_retained_clips:
        from tools.seed_retained_clip_ui import verify_clips
        added -= verify_clips(container)
    assert len(added)==1 and all(Path(p).name.startswith('Reference-') for p in added),'Expected one reused verified handoff copy only'
    expected=fixture(VALID)[2]['vocalsSHA256']
    assert all(current[p]==expected for p in added),'Handoff copies differ from verified vocals'
    assert inventory(jobs)==baseline['jobs'],'Navigation/authorization started or changed processing jobs'
    print('SYNTHETIC_SEPARATION_HANDOFF_UI: one reused verified copy; originals and corrupt pair retained; no processing started')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['seed','check']);parser.add_argument('container',type=Path)
    parser.add_argument('--allow-retained-clips',action='store_true')
    args=parser.parse_args()
    if args.mode=='seed':seed(args.container)
    else:check(args.container,allow_retained_clips=args.allow_retained_clips)
