#!/usr/bin/env python3
"""Fetch the pinned BeeWare iOS CPython SDK; never install desktop Python binaries."""
import argparse, hashlib, pathlib, tarfile, urllib.request
URL='https://github.com/beeware/Python-Apple-support/releases/download/3.13-b18/Python-3.13-iOS-support.b18.tar.gz'
SHA256='d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d'
def verify(path):
    with path.open('rb') as source:
        digest=hashlib.file_digest(source,'sha256').hexdigest()
    if digest!=SHA256: raise ValueError('CPython archive digest mismatch; refusing extraction')
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--archive',type=pathlib.Path); ap.add_argument('--destination',required=True,type=pathlib.Path);args=ap.parse_args()
    args.destination.mkdir(parents=True,exist_ok=True)
    archive=args.archive or args.destination/'Python-3.13-iOS-support.b18.tar.gz'
    if not args.archive:
        with urllib.request.urlopen(URL,timeout=90) as r, archive.open('wb') as out:
            while chunk:=r.read(1024*1024):out.write(chunk)
    verify(archive)
    with tarfile.open(archive) as tf: tf.extractall(args.destination,filter='data')
    print('Verified CPython 3.13.18 iOS b18 runtime extracted')
if __name__=='__main__':main()
