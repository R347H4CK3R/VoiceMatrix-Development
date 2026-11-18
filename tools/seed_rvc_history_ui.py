"""Synthetic simulator-only history fixture. No model inference or production hook."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import wave

ID = '9479750A-0204-4C84-AB2A-F193D8E826A1'
NAME = 'UI synthetic history fixture.wav'
FILE = f'RVC-preview-{ID}.wav'


def payload():
    stream = io.BytesIO()
    with wave.open(stream, 'wb') as wav:
        wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
        wav.writeframes(b'\x00\x00' * 1600)
    return stream.getvalue()


def fixture():
    data = payload()
    sha = hashlib.sha256(data).hexdigest()
    # Swift JSONEncoder's default Date is seconds since 2001-01-01.
    context = dict(inputName=NAME, inputSHA256=sha, inputBytes=len(data),
                   modelSHA256={'hubert': 'b'*64, 'synthesizer': 'c'*64},
                   settings=dict(indexRate=0, semitones=0, refinePitch=False),
                   startedAt=800000000, completedAt=800000042)
    return data, dict(schemaVersion=1, id=ID, file=FILE, createdAt=800000042,
                      elapsedSeconds=42, bytes=len(data), sha256=sha, context=context)


def seed(container):
    root = container / 'Library/Application Support/RVCPreview/Results'
    root.mkdir(parents=True, exist_ok=True)
    data, receipt = fixture()
    # Never overwrite any existing app file. Owned fresh CI simulator only.
    with (root / FILE).open('xb') as f:
        f.write(data)
    with (root / (Path(FILE).stem + '.json')).open('x') as f:
        json.dump(receipt, f, sort_keys=True)


def check(container):
    data, receipt = fixture()
    root = container / 'Library/Application Support/RVCPreview/Results'
    assert (root / FILE).read_bytes() == data, 'Original synthetic audio changed'
    assert json.loads((root / (Path(FILE).stem + '.json')).read_text()) == receipt
    cache = container / 'Library/Caches/RVCPreview'
    copies = list(cache.glob('rvc-action-*/' + FILE))
    assert len(copies) == 1, 'Expected one reused verified action snapshot'
    assert not copies[0].is_symlink() and not copies[0].parent.is_symlink()
    assert copies[0].read_bytes() == data, 'Verified action snapshot differs'
    print('SYNTHETIC_RVC_HISTORY_UI_EVIDENCE: original retained; one matching action snapshot')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['seed', 'check'])
    parser.add_argument('container', type=Path)
    args = parser.parse_args()
    {'seed': seed, 'check': check}[args.mode](args.container)
