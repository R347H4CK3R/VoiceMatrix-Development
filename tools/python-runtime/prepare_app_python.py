#!/usr/bin/env python3
"""Stage pinned production code; repeat generation uses verified local artifacts."""
import hashlib,json,pathlib,re,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
def main():
    for name,entry in json.loads((ROOT/'tools/python-runtime/notice-hashes.json').read_text()).items():
        actual=(ROOT/'VoiceMatrix/Resources/PythonRuntimeNotices'/name).read_bytes()
        if hashlib.sha256(actual).hexdigest()!=entry['sha256']:raise ValueError('Runtime notice digest mismatch')
    sdk=ROOT/'Vendors/Python';archive=sdk/'Python-3.13-iOS-support.b18.tar.gz'
    command=[sys.executable,str(ROOT/'tools/python-runtime/prepare_python_runtime.py'),'--destination',str(sdk)]
    if archive.is_file():command+=['--archive',str(archive)]
    subprocess.run(command,check=True)  # Existing archive is reverified before extraction.
    requirements=ROOT/'tools/python-runtime/requirements-ios-resolver.txt'
    wheels=ROOT/'.python-runtime/wheels';wheels.mkdir(parents=True,exist_ok=True)
    expected=set(re.findall(r'--hash=sha256:([0-9a-f]{64})',requirements.read_text()))
    available={hashlib.sha256(p.read_bytes()).hexdigest() for p in wheels.glob('*.whl')}
    if not expected.issubset(available):
        subprocess.run([sys.executable,'-m','pip','download','--require-hashes','--no-deps','--only-binary=:all:','-r',str(requirements),'--dest',str(wheels)],check=True)
    target=ROOT/'.python-runtime/app_packages'
    if target.exists():shutil.rmtree(target)
    target.mkdir(parents=True)
    subprocess.run([sys.executable,'-m','pip','install','--no-index','--find-links',str(wheels),'--require-hashes','--no-deps','--no-compile','-r',str(requirements),'--target',str(target)],check=True)
    for module in ('voicematrix_resolver.py','voicematrix_mkv_stage.py'):
        shutil.copy2(ROOT/'python-resolver'/module,target/module)
    for p in target.rglob('__pycache__'):shutil.rmtree(p)
    for directory in ('bin','share'):
        if (target/directory).exists():shutil.rmtree(target/directory)
    for suffix in ('*.pyc','*.so','*.dylib','*tls-test*'):
        if list(target.rglob(suffix)):raise RuntimeError('Forbidden generated content in production Python bundle')
if __name__=='__main__':main()
