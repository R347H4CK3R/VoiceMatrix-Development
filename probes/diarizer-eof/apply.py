"""Diagnostic-only exact-source patch. Not a production dependency resolver."""
import hashlib,json,pathlib,subprocess,sys
HERE=pathlib.Path(__file__).resolve().parent
def sha(data): return hashlib.sha256(data).hexdigest()
def apply(checkout, evidence):
    manifest=json.loads((HERE/'manifest.json').read_text())
    patch=HERE/'fluid-eof.patch'
    assert sha(patch.read_bytes())==manifest['patchSHA256'], 'Patch identity mismatch'
    revision=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
    assert revision==manifest['revision'], 'Unexpected dependency revision'
    assert not subprocess.check_output(['git','-C',str(checkout),'status','--porcelain'],text=True).strip(), 'Dependency checkout not clean'
    for name, hashes in manifest['files'].items():
        assert sha((checkout/name).read_bytes())==hashes['before'], 'Unexpected upstream file: '+name
    subprocess.run(['git','-C',str(checkout),'apply','--check',str(patch)],check=True)
    subprocess.run(['git','-C',str(checkout),'apply',str(patch)],check=True)
    for name, hashes in manifest['files'].items():
        assert sha((checkout/name).read_bytes())==hashes['after'], 'Patched file differs: '+name
    evidence.mkdir(parents=True,exist_ok=True)
    (evidence/'dependency-patch-proof.json').write_text(json.dumps(manifest,indent=2)+'\n')
    target=checkout/'Tests/FluidAudioTests/Diarizer/Offline/EOFTimelineTests.swift'
    assert not target.exists(), 'Test collision'
    test=(HERE/'EOFTimelineTests.swift').read_bytes()
    target.write_bytes(test)
    (evidence/'dependency-test-proof.json').write_text(json.dumps({'path':str(target.relative_to(checkout)),'sha256':sha(test)},indent=2)+'\n')
if __name__=='__main__': apply(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
