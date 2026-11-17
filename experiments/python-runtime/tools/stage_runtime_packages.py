#!/usr/bin/env python3
"""Build clean, hash-pinned production and test-host resource trees."""
import argparse, pathlib, shutil, subprocess, sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--wheels',type=pathlib.Path);args=parser.parse_args()
    stage=ROOT/'.runtime-stage'
    if stage.exists():shutil.rmtree(stage)
    prod=stage/'production_packages';prod.mkdir(parents=True)
    command=[sys.executable,'-m','pip','install','--require-hashes','--no-deps','--no-compile','--disable-pip-version-check','-r',str(ROOT/'tools/requirements-ios-resolver.txt'),'--target',str(prod)]
    if args.wheels:command+=['--no-index','--find-links',str(args.wheels)]
    subprocess.run(command,check=True)
    shutil.copy2(ROOT/'app_packages/voicematrix_resolver.py',prod/'voicematrix_resolver.py')
    for cache in prod.rglob('__pycache__'):shutil.rmtree(cache)
    if (prod/'bin').exists():shutil.rmtree(prod/'bin')
    harness=stage/'app_packages';shutil.copytree(prod,harness)
    (harness/'voicematrix_resolver.py').rename(harness/'production_voicematrix_resolver.py')
    shutil.copy2(ROOT/'tests/runtime-harness/app_packages/voicematrix_resolver.py',harness/'voicematrix_resolver.py')
    # Disposable self-signed test fixture only; never a credential for a real service.
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes',
                    '-keyout',str(harness/'tls-test-key.pem'),'-out',str(harness/'tls-test-cert.pem'),
                    '-subj','/CN=www.youtube.com','-days','1'],check=True,
                   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=15)
    for forbidden in ('*.pyc','*.so','*.dylib'):
        if list(stage.rglob(forbidden)):raise RuntimeError('Unexpected cache or native module in pure Python dependencies')
    print('Fresh hash-verified production and native harness packages staged')
if __name__=='__main__':main()
