"""CI-only FFmpeg 9.0.2 from FFmpeg.org-linked Gyan Windows builds.

Provenance: https://ffmpeg.org/download.html -> https://www.gyan.dev/ffmpeg/builds/
Digest independently published by vendor checksum and GitHub release asset:
https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-essentials_build.zip.sha256
https://github.com/GyanD/codexffmpeg/releases/expanded_assets/9.0.2
No package installation, registry changes, or unpinned/latest fallback.
"""
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import time
import urllib.request
import zipfile

VERSION = '9.0.2'
ROOT = 'ffmpeg-9.0.2-essentials_build'
SHA256 = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
SIZE = 114768076
URLS = (
    'https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-essentials_build.zip',
    'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip',
)
MAX_ARCHIVE = 128 * 1024 * 1024
MAX_FILE = 256 * 1024 * 1024
MAX_TOTAL = 768 * 1024 * 1024


def verify_archive(path, expected=SHA256, size=SIZE):
    if path.stat().st_size != size or size > MAX_ARCHIVE:
        raise ValueError('Archive byte count mismatch')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise ValueError('Archive SHA-256 mismatch')


def extract_checked(archive, destination):
    """Caller must verify entire archive hash before extraction. Never execute members."""
    if destination.exists() or destination.is_symlink():
        raise ValueError('Destination already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.ffmpeg-stage-', dir=destination.parent))
    try:
        with zipfile.ZipFile(archive) as bundle:
            members=bundle.infolist()
            if len(members)>512: raise ValueError('Too many ZIP entries')
            total=0;seen=set()
            for member in members:
                # ZipInfo normalizes native separators and truncates NULs on read.
                # Validate the original central-directory spelling, not only its alias.
                name=member.orig_filename
                if name != member.filename:
                    raise ValueError('Unsafe ZIP path: normalized archive name')
                parts=PurePosixPath(name).parts
                if ('\\' in name or ':' in name or not parts or parts[0]!=ROOT or
                    any(p in ('..','.') or p.endswith((' ','.')) for p in parts) or
                    name.startswith('/') or '\x00' in name or '\n' in name or '\r' in name):
                    raise ValueError('Unsafe ZIP path')
                key=name.rstrip('/').casefold()
                if key in seen: raise ValueError('Duplicate ZIP path')
                seen.add(key)
                mode=(member.external_attr>>16)&0xFFFF
                if stat.S_IFMT(mode) not in (0,stat.S_IFREG,stat.S_IFDIR):
                    raise ValueError('Nonregular ZIP entry')
                if member.flag_bits&1: raise ValueError('Encrypted ZIP entry')
                total+=member.file_size
                if member.file_size>MAX_FILE or total>MAX_TOTAL: raise ValueError('ZIP size limit')
            required={ROOT+'/bin/ffmpeg.exe',ROOT+'/bin/ffprobe.exe'}
            if not required.issubset({m.filename for m in members if not m.is_dir()}):
                raise ValueError('Missing media tools')
            for member in members:
                output=stage.joinpath(*PurePosixPath(member.filename).parts)
                if member.is_dir(): output.mkdir(parents=True,exist_ok=True);continue
                output.parent.mkdir(parents=True,exist_ok=True)
                copied=0
                with bundle.open(member) as source, output.open('xb') as target:
                    while block:=source.read(1024*1024):
                        copied+=len(block)
                        if copied>member.file_size or copied>MAX_FILE: raise ValueError('ZIP member overflow')
                        target.write(block)
                if copied!=member.file_size: raise ValueError('Truncated ZIP member')
            for executable in required:
                with (stage/executable).open('rb') as stream:
                    if stream.read(2)!=b'MZ': raise ValueError('Not a Windows executable')
        # Windows rename refuses an existing destination. Never overwrite an install.
        if destination.exists(): raise ValueError('Destination appeared during setup')
        stage.rename(destination)
        return destination/ROOT/'bin'
    finally:
        if stage.exists(): shutil.rmtree(stage)


def download(path):
    failures=[]
    for url in URLS:
        try:
            deadline=time.monotonic()+240
            request=urllib.request.Request(url,headers={'User-Agent':'VoiceMatrix-CI-pinned-ffmpeg'})
            with urllib.request.urlopen(request,timeout=30) as response, path.open('wb') as target:
                if not response.url.startswith('https://'): raise ValueError('Insecure redirect')
                count=0
                while block:=response.read(1024*1024):
                    count+=len(block)
                    if count>MAX_ARCHIVE or time.monotonic()>deadline: raise ValueError('Download bounds exceeded')
                    target.write(block)
            verify_archive(path)
            return
        except Exception as error:
            failures.append(type(error).__name__)
            path.unlink(missing_ok=True)
    raise RuntimeError('Both pinned vendor sources failed: '+', '.join(failures))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args()
    if os.name!='nt' or os.environ.get('GITHUB_ACTIONS')!='true' or not os.environ.get('GITHUB_PATH'):
        raise SystemExit('Only Windows GitHub Actions runners are supported')
    destination=args.destination.resolve()
    if '\n' in str(destination) or '\r' in str(destination): raise ValueError('Unsafe PATH entry')
    with tempfile.TemporaryDirectory(prefix='verified-ffmpeg-') as temp:
        archive=Path(temp)/'build.zip'
        download(archive)
        binary=extract_checked(archive,destination)
    with open(os.environ['GITHUB_PATH'],'a',encoding='utf-8') as path:
        path.write(str(binary)+'\n')
    print('Pinned FFmpeg '+VERSION+' verified and added to subsequent CI step PATH; SHA256 '+SHA256)

if __name__=='__main__':main()
