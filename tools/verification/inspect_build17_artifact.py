"""Independent read-only inspection of one pinned, authenticated build17 artifact."""
import argparse, hashlib, json, os, pathlib, re, shutil, stat, subprocess, sys, zipfile

REPO = 'R347H4CK3R/VoiceMatrix-Development'
COMMIT = '0064f4acba7d71a13e1730707fdd4cf683909c4c'
RUN = 44253624669
ARTIFACT = 14406432049
ZIP_SHA = '45a91aa055cf40d9ff23b1691093e4bbf2991ee6cf336c254ef448ed8dfafbe4'
ZIP_SIZE = 1330145676
IPA = 'VoiceMatrix-0.4.14-build17.ipa'
OUTER_FILES = {IPA, 'python-runtime-inspection.log', 'python-runtime-inspection.json',
               'character-inspection.json', 'character-ipa.sha256', 'source-proof.json',
               'dependency-notices.json', 'assets.json', 'packaging-status.json',
               'vendor-before.json', 'vendor-after.json'}

def digest(path):
    with pathlib.Path(path).open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()

def validate_metadata(meta, run):
    if (meta.get('id'), meta.get('name'), meta.get('size_in_bytes'), meta.get('expired'), meta.get('digest')) != (ARTIFACT, 'Character-test-IPA', ZIP_SIZE, False, 'sha256:' + ZIP_SHA):
        raise ValueError('Artifact identity, expiration, size or digest mismatch')
    wr = meta.get('workflow_run', {})
    if wr.get('id') != RUN or wr.get('head_sha') != COMMIT:
        raise ValueError('Artifact belongs to a different run/source')
    if run.get('status') != 'completed' or run.get('conclusion') != 'success' or run.get('path') != '.github/workflows/iphone-build17.yml':
        raise ValueError('Expected successful build17 workflow')
    if run.get('id') != RUN or run.get('head_sha') != COMMIT or run.get('repository', {}).get('full_name') != REPO:
        raise ValueError('Run repository/source mismatch')

def checked_members(z, limit):
    seen = set(); total = 0
    for item in z.infolist():
        name = item.filename
        path = pathlib.PurePosixPath(name)
        if not name or '\\' in name or '\x00' in name or path.is_absolute() or any(p in ('', '.', '..') for p in name.rstrip('/').split('/')) or ':' in name:
            raise ValueError('Unsafe archive path')
        key = name.rstrip('/').casefold()
        if key in seen: raise ValueError('Duplicate/colliding archive path')
        seen.add(key)
        mode = item.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR) or item.flag_bits & 1:
            raise ValueError('Link, special or encrypted archive entry')
        if kind == stat.S_IFDIR and not item.is_dir(): raise ValueError('Ambiguous directory')
        total += item.file_size
        if total > limit or item.file_size > limit: raise ValueError('Archive extraction budget exceeded')
    return z.infolist()

def extract(z, destination, members):
    destination.mkdir(parents=True, exist_ok=False)
    for item in members:
        out = destination / item.filename
        if item.is_dir(): out.mkdir(parents=True, exist_ok=True); continue
        out.parent.mkdir(parents=True, exist_ok=True)
        with z.open(item) as source, out.open('xb') as target:
            shutil.copyfileobj(source, target, 1024 * 1024)
        if out.stat().st_size != item.file_size: raise ValueError('Truncated extraction')

def inspect(archive, target, output):
    target = target.resolve(); output = output.resolve(); archive = archive.resolve()
    if subprocess.check_output(['git', '-C', str(target), 'rev-parse', 'HEAD'], text=True).strip() != COMMIT:
        raise ValueError('Incorrect inspection source checkout')
    if archive.stat().st_size != ZIP_SIZE or digest(archive) != ZIP_SHA:
        raise ValueError('Artifact ZIP does not match authenticated identity')
    output.mkdir(parents=True, exist_ok=True)
    unpacked = output.parent / 'artifact-unpacked'
    with zipfile.ZipFile(archive) as z:
        members = checked_members(z, 4 * 1024**3)
        if {i.filename for i in members} != OUTER_FILES: raise ValueError('Unexpected artifact inventory')
        if any(i.file_size > 20 * 1024**2 for i in members if i.filename != IPA): raise ValueError('Oversized receipt')
        extract(z, unpacked, members)
    ipa = unpacked / IPA
    checksum = (unpacked / 'character-ipa.sha256').read_text()
    match = re.fullmatch(r'([0-9a-f]{64})  ' + re.escape(IPA) + r'\n?', checksum)
    if not match or digest(ipa) != match[1]: raise ValueError('IPA checksum mismatch')
    app_root = output.parent / 'extracted-ipa'
    with zipfile.ZipFile(ipa) as z:
        members = checked_members(z, 8 * 1024**3)
        if any(not i.filename.startswith('Payload/') for i in members): raise ValueError('Unexpected IPA root')
        extract(z, app_root, members)
    app = app_root / 'Payload/VoiceMatrix.app'
    if {p.name for p in (app_root / 'Payload').iterdir()} != {'VoiceMatrix.app'}: raise ValueError('Unexpected app payload')
    source = json.loads((app / 'VoiceMatrix-Source-Proof.json').read_text())
    if source != json.loads((unpacked / 'source-proof.json').read_text()): raise ValueError('Embedded source receipt differs')
    env = dict(os.environ, GITHUB_SHA=COMMIT)
    # Re-derive the lock from pinned historical bytes, not package-supplied provenance.
    lock = output / 'Package.resolved'
    lock.write_bytes((target / 'tests/fixtures/build17-original-Package.resolved').read_bytes())
    subprocess.run([sys.executable, '-m', 'tools.frozen_vendored_graph', str(lock)], cwd=target, env=env, check=True)
    embedded_lock = app / 'F5TTS/DependencyNotices/Package.resolved'
    if embedded_lock.read_bytes() != lock.read_bytes(): raise ValueError('Embedded dependency graph differs')
    expected = output / 'expected-source-proof.json'
    subprocess.run([sys.executable, '-m', 'tools.character_evidence', 'source', str(lock), str(expected)], cwd=target, env=env, check=True)
    if source != json.loads(expected.read_text()): raise ValueError('Source proof does not match exact checkout and lock')
    status = json.loads((unpacked / 'packaging-status.json').read_text())
    if (status.get('sourceCommit'), status.get('version'), status.get('build')) != (COMMIT, '0.4.14', '17'):
        raise ValueError('Packaging identity differs')
    def command(name, args):
        with (output / name).open('w') as log:
            subprocess.run([sys.executable] + args, cwd=target, env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
    command('character-inspection.json', ['tools/character_package.py', 'inspect', str(ipa), '--expected-version', '0.4.14', '--expected-build', '17', '--dependency-proof', str(unpacked / 'dependency-notices.json')])
    command('diarization-inspection.log', ['tools/bundle_diarization.py', '--inspect-ipa', str(ipa)])
    command('asr-inspection.log', ['tools/bundle_asr.py', '--inspect-ipa', str(ipa)])
    # This retrieves and validates upstream hash-pinned SDK/wheels independently.
    command('prepare-python.log', ['tools/python-runtime/prepare_app_python.py'])
    command('python-inspection.log', ['tools/python-runtime/verify_python_bundle.py', str(app), '--json-out', str(output / 'python-inspection.json')])
    (output / 'inspection-summary.json').write_text(json.dumps(dict(repository=REPO, sourceCommit=COMMIT, runID=RUN, artifactID=ARTIFACT, artifactSHA256=ZIP_SHA, ipaSHA256=match[1], passed=True, physicalDeviceVerified=False, nativeBehaviorVerified=False, published=False, scope='Independent archive, exact-source, pinned resources and runtime inspection only'), indent=2) + '\n')

if __name__ == '__main__':
    p = argparse.ArgumentParser(); sub = p.add_subparsers(dest='command', required=True)
    m = sub.add_parser('metadata'); m.add_argument('artifact', type=pathlib.Path); m.add_argument('run', type=pathlib.Path)
    i = sub.add_parser('inspect'); i.add_argument('archive', type=pathlib.Path); i.add_argument('target', type=pathlib.Path); i.add_argument('output', type=pathlib.Path)
    a = p.parse_args()
    if a.command == 'metadata': validate_metadata(json.loads(a.artifact.read_text()), json.loads(a.run.read_text()))
    else: inspect(a.archive, a.target, a.output)
