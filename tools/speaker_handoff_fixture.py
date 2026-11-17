"""Owned-simulator test-only fixture installation and preservation checks; no app hooks."""
import argparse,hashlib,json,pathlib,shutil,subprocess,uuid

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inventory(root):
    assert root.is_dir() and not root.is_symlink()
    out={}
    for p in root.rglob('*'):
        assert not p.is_symlink(),'Fixture/data symlinks prohibited'
        if p.is_file():out[p.relative_to(root).as_posix()]=digest(p)
    return out

def main():
    a=argparse.ArgumentParser();a.add_argument('container',type=pathlib.Path);a.add_argument('fixture',type=pathlib.Path);a.add_argument('receipt',type=pathlib.Path);a.add_argument('--simulator-id',required=True);a.add_argument('--verify',action='store_true');args=a.parse_args()
    container=args.container.resolve(strict=True)
    # simctl is authoritative for bundle membership; path UUID alone is not identity.
    simulator=args.simulator_id
    assert str(uuid.UUID(simulator)).lower()==simulator.lower()
    reported=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',simulator,'com.voicematrix.app','data'],text=True).strip())
    assert reported.is_absolute() and reported.resolve(strict=True)==container,'Not the selected app data container'
    assert container.parts[-6:-1]==(simulator,'data','Containers','Data','Application'),'Wrong owned simulator layout'
    assert container.parents[5].name=='Devices' and container.parents[6].name=='CoreSimulator'
    uuid.UUID(container.name)
    identity={'simulatorRoot':str(container.parents[4]),'simulatorID':simulator,'bundleID':'com.voicematrix.app'}
    support=container/'Library/Application Support';receipt=args.receipt
    fixture=args.fixture/'Application Support'
    if not args.verify:
        assert not receipt.exists(),'Do not overwrite receipt'
        support.mkdir(parents=True,exist_ok=True)
        files=inventory(fixture)
        assert set(p.name for p in fixture.iterdir())=={'LocalVideoStudio','CharacterReferences'}
        for name in ['LocalVideoStudio','CharacterReferences']:
            assert not (support/name).exists(),'Use a fresh owned simulator, never replace app data'
        for name in ['LocalVideoStudio','CharacterReferences']:shutil.copytree(fixture/name,support/name)
        assert all(digest(support/p)==h for p,h in files.items())
        receipt.write_text(json.dumps({'container':str(container),'identity':identity,'files':files},sort_keys=True,indent=2)+'\n')
    else:
        before=json.loads(receipt.read_text());assert before['identity']==identity,'Owned simulator/app identity changed'
        for name in ['LocalVideoStudio','CharacterReferences']:
            actual={name+'/'+p:h for p,h in inventory(support/name).items()}
            assert actual=={p:h for p,h in before['files'].items() if p.startswith(name+'/')},'Retained job/library changed'
        media={p.relative_to(support).as_posix() for p in support.rglob('*') if p.is_file() and p.suffix.lower() in {'.wav','.caf','.m4a','.mp3','.aiff','.flac'}}
        assert media=={p for p in before['files'] if pathlib.Path(p).suffix=='.wav'},'Unexpected generated media'
        print(json.dumps({'identity':identity,'beforeContainer':before['container'],'afterContainer':str(container),'verifiedFileCount':len(before['files']),'noExtraMedia':True},sort_keys=True))
if __name__=='__main__':main()
