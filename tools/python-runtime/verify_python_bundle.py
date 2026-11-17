#!/usr/bin/env python3
"""Inspect built/extracted .app against pinned archives, not staged working files."""
import argparse,hashlib,json,pathlib,plistlib,re,tarfile
from runtime_inventory import verify_signed_native,sha,wheel_inventory
from prepare_python_runtime import SHA256 as SDK_SHA,verify as verify_sdk
ROOT=pathlib.Path(__file__).resolve().parents[2]
def inspect(app):
    app=app.resolve();assert app.is_dir(),'Built/extracted .app missing'
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='com.voicematrix.app'
    assert info['CFBundleShortVersionString']=='0.4.13' and str(info['CFBundleVersion'])=='16'
    def reject_symlinks(directory):
        assert not directory.is_symlink(),f'Symlinked runtime root: {directory.name}'
        for path in directory.rglob('*'):
            assert not path.is_symlink(),f'Symlink in runtime tree: {path.relative_to(app)}'
    for directory in (app/'python',app/'app_packages',app/'PythonRuntimeNotices'):
        assert directory.is_dir(),'Required runtime resource tree missing'
        reject_symlinks(directory)
    proof={'schemaVersion':1,'version':'0.4.13','build':'16','sdkArchiveSHA256':SDK_SHA,'native':{},'resources':{},'wheels':[]}
    def resource(relative,expected):
        actual=(app/relative).read_bytes();assert actual==expected,f'Resource mismatch: {relative}'
        proof['resources'][relative]={'bytes':len(actual),'sha256':sha(actual)}
    def native(relative,expected):
        actual=(app/relative).read_bytes();identity=verify_signed_native(expected,actual)
        proof['native'][relative]={'upstreamBinarySHA256':sha(expected),'packagedBinarySHA256':sha(actual),'signingAwareIdentity':identity}
    notices=json.loads((ROOT/'tools/python-runtime/notice-hashes.json').read_text())
    for name,entry in notices.items():
        relative='PythonRuntimeNotices/'+name;actual=(app/relative).read_bytes()
        assert sha(actual)==entry['sha256'],f'Runtime notice changed: {name}'
        proof['resources'][relative]={'bytes':len(actual),'sha256':sha(actual)}
    archive=ROOT/'Vendors/Python/Python-3.13-iOS-support.b18.tar.gz';verify_sdk(archive)
    extension_count=0;framework_allow={}
    with tarfile.open(archive) as tar:
        template=plistlib.loads(tar.extractfile('Python.xcframework/build/iOS-dylib-Info-template.plist').read())
        def framework_metadata(module):
            folder=f'Frameworks/{module}.framework'
            reject_symlinks(app/folder)
            framework_allow.setdefault(folder,set()).update({module,'Info.plist','_CodeSignature/CodeResources'})
            if module=='Python':
                expected=tar.extractfile('Python.xcframework/ios-arm64/Python.framework/Info.plist').read()
                resource(folder+'/Info.plist',expected)
            else:
                expected=dict(template,CFBundleExecutable=module,CFBundleIdentifier=('com.voicematrix.app.'+module).replace('_','-'))
                actual=(app/folder/'Info.plist').read_bytes()
                assert plistlib.loads(actual)==expected,'Generated Python framework metadata changed'
                proof['resources'][folder+'/Info.plist']={'bytes':len(actual),'sha256':sha(actual)}
        framework_metadata('Python')
        for member in tar.getmembers():
            if not member.isfile():continue
            name=member.name
            if name=='Python.xcframework/ios-arm64/Python.framework/Python':
                native('Frameworks/Python.framework/Python',tar.extractfile(member).read());continue
            prefix=next((p for p in ('Python.xcframework/lib/','Python.xcframework/ios-arm64/lib-arm64/') if name.startswith(p)),None)
            if not prefix:continue
            relative='python/lib/'+name[len(prefix):]
            if relative.startswith('python/lib/python3.13/test/'):continue
            if '__pycache__' in relative or relative.endswith(('.pyc','.dylib')):continue
            expected=tar.extractfile(member).read()
            if relative.endswith('.so'):
                module=pathlib.PurePosixPath(relative).name.split('.')[0]
                framework=f'Frameworks/{module}.framework/{module}'
                native(framework,expected);extension_count+=1
                framework_metadata(module)
                marker=relative[:-3]+'.fwork'
                resource(marker,(framework+'\n').encode())
                origin=f'Frameworks/{module}.framework/{module}.origin'
                resource(origin,(marker+'\n').encode())
                framework_allow[f'Frameworks/{module}.framework'].add(module+'.origin')
            elif relative.endswith('.xcprivacy'):
                module=pathlib.PurePosixPath(relative).stem
                resource(f'Frameworks/{module}.framework/PrivacyInfo.xcprivacy',expected)
                framework_allow.setdefault(f'Frameworks/{module}.framework',set()).add('PrivacyInfo.xcprivacy')
            else:resource(relative,expected)
    for folder,allowed in framework_allow.items():
        for path in (app/folder).rglob('*'):
            if path.is_file():
                relative=path.relative_to(app/folder).as_posix()
                assert relative in allowed,f'Unexpected runtime framework file: {folder}/{relative}'
                if relative=='_CodeSignature/CodeResources':
                    actual=path.read_bytes();assert isinstance(plistlib.loads(actual),dict),'Malformed signing resource metadata'
                    proof['resources'][folder+'/'+relative]={'bytes':len(actual),'sha256':sha(actual)}
    for directory in (app/'python',app/'PythonRuntimeNotices'):
        for path in directory.rglob('*'):
            if path.is_file():assert path.relative_to(app).as_posix() in proof['resources'],f'Unexpected runtime resource: {path.relative_to(app)}'
    assert extension_count==68 and len(proof['native'])==69,'Pinned native inventory incomplete'
    requirements=(ROOT/'tools/python-runtime/requirements-ios-resolver.txt').read_bytes()
    proof['requirementsSHA256']=sha(requirements)
    expected_wheels=set(re.findall(r'--hash=sha256:([0-9a-f]{64})',requirements.decode()))
    found=set();wheel_paths=set()
    for wheel in sorted((ROOT/'.python-runtime/wheels').glob('*.whl')):
        digest=sha(wheel.read_bytes());assert digest in expected_wheels,'Unexpected wheel'
        found.add(digest);inventory=wheel_inventory(wheel)
        proof['wheels'].append({'filename':wheel.name,'sha256':digest,'resourceCount':len(inventory)})
        for relative,entry in inventory.items():
            actual=(app/'app_packages'/relative).read_bytes()
            assert len(actual)==entry['bytes'] and sha(actual)==entry['sha256'],f'Wheel resource mismatch: {relative}'
            proof['resources']['app_packages/'+relative]=entry;wheel_paths.add(relative)
    assert found==expected_wheels,'Missing pinned wheel'
    resource('app_packages/voicematrix_resolver.py',(ROOT/'python-resolver/voicematrix_resolver.py').read_bytes())
    for path in (app/'app_packages').rglob('*'):
        if not path.is_file():continue
        relative=path.relative_to(app/'app_packages').as_posix()
        generated=relative.endswith(('.dist-info/RECORD','.dist-info/INSTALLER','.dist-info/REQUESTED'))
        assert relative in wheel_paths or relative=='voicematrix_resolver.py' or generated,f'Unexpected Python resource: {relative}'
        if generated:
            actual=path.read_bytes();proof['resources']['app_packages/'+relative]={'bytes':len(actual),'sha256':sha(actual)}
    assert not list(app.rglob('*.pyc')),'Bytecode caches unexpectedly packaged'
    proof['verificationScope']='Exact pinned wheel+stdlib resources and full arm64 SDK slice bytes; only LC_CODE_SIGNATURE, terminal code-signature bytes/alignment, and LINKEDIT signing sizes normalized. Headers, all other load commands, exports, rebases, chained fixups, symbols and every remaining byte must match. Stripping or install-name edits rejected.'
    return proof

def main():
    parser=argparse.ArgumentParser();parser.add_argument('app',type=pathlib.Path);parser.add_argument('--json-out',type=pathlib.Path);args=parser.parse_args()
    proof=inspect(args.app)
    if args.json_out:args.json_out.write_text(json.dumps(proof,sort_keys=True,indent=2)+'\n')
    print(f"Verified actual build16 app: {len(proof['native'])} native binaries, {len(proof['resources'])} pinned resources, {len(proof['wheels'])} wheel identities")
if __name__=='__main__':main()
