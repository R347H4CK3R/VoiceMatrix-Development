"""Independent hostile MP4 mutations against the actual native export executable.

Only fixture box location/editing lives here; no production parsing rules are emulated.
macOS native failures must remain failures, never converted into skips.
"""
import hashlib
import json
import pathlib
import platform
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def u32(data, offset):
    return struct.unpack_from('>I', data, offset)[0]


def box(kind, payload=b''):
    return struct.pack('>I4s', len(payload) + 8, kind) + payload


def children(data, start, end):
    result = []
    while start < end:
        size = u32(data, start)
        if size < 8 or start + size > end:
            raise ValueError('fixture container is not a complete small-box sequence')
        result.append((start, start + size, bytes(data[start + 4:start + 8])))
        start += size
    return result


def path(data, *kinds):
    start, end, ancestors = 0, len(data), []
    for kind in kinds:
        match = next(b for b in children(data, start, end) if b[2] == kind)
        ancestors.append(match)
        start, end = match[0] + 8, match[1]
    return ancestors


def put32(data, offset, value):
    struct.pack_into('>I', data, offset, value)


def append_child(data, kinds, child):
    parents = path(data, *kinds)
    insertion = parents[-1][1]
    for start, end, _ in parents:
        put32(data, start, end - start + len(child))
    data[insertion:insertion] = child


def mutate(original, name):
    data = bytearray(original)
    table_path = (b'moov', b'trak', b'mdia', b'minf', b'stbl')
    def table(kind):
        return path(data, *table_path, kind)[-1][0]
    if name == 'unsupported-codec':
        data[table(b'stsd') + 20:table(b'stsd') + 24] = b'avc3'
    elif name == 'encrypted-codec':
        data[table(b'stsd') + 20:table(b'stsd') + 24] = b'encv'
    elif name == 'fragmented':
        data += box(b'moof')
    elif name == 'encrypted-samples':
        append_child(data, table_path, box(b'senc', b'\0' * 8))
    elif name == 'nonidentity-edit':
        entry = struct.pack('>IiHH', 100, 1, 1, 0)
        append_child(data, (b'moov', b'trak'), box(b'edts', box(b'elst', b'\0' * 4 + struct.pack('>I', 1) + entry)))
    elif name == 'composition-offset':
        count = u32(data, table(b'stsz') + 16)
        append_child(data, table_path, box(b'ctts', b'\0' * 4 + struct.pack('>III', 1, count, 1)))
    elif name == 'huge-stts-count':
        put32(data, table(b'stts') + 12, 0xffffffff)
    elif name == 'huge-sample-count':
        put32(data, table(b'stsz') + 16, 0xffffffff)
    elif name == 'sample-count-mismatch':
        put32(data, table(b'stsz') + 16, u32(data, table(b'stsz') + 16) - 1)
    elif name == 'outside-mdat':
        put32(data, table(b'stco') + 16, 0)
    elif name == 'past-file-offset':
        put32(data, table(b'stco') + 16, len(data) + 4096)
    elif name == 'zero-first-chunk':
        put32(data, table(b'stsc') + 16, 0)
    elif name == 'bad-sync-index':
        put32(data, table(b'stss') + 16, 0xffffffff)
    elif name == 'description-count-mismatch':
        put32(data, table(b'stsd') + 12, 2)
    elif name == 'external-data-reference':
        dref = path(data, b'moov', b'trak', b'mdia', b'minf', b'dinf', b'dref')[-1][0]
        # FullBox + entry_count, then url FullBox flags. No external payload is fetched.
        put32(data, dref + 24, 0)
    elif name == 'zero-timescale':
        mdhd = path(data, b'moov', b'trak', b'mdia', b'mdhd')[-1][0]
        assert data[mdhd + 8] == 0
        put32(data, mdhd + 20, 0)
    elif name == 'duplicate-stts':
        start = table(b'stts')
        duplicate = bytes(data[start:start + u32(data, start)])
        append_child(data, table_path, duplicate)
    elif name == 'overlapping-chunks':
        stco = table(b'stco')
        assert u32(data, stco + 12) > 1
        put32(data, stco + 20, u32(data, stco + 16))
    elif name == 'oversized-moov':
        put32(data, path(data, b'moov')[-1][0], 0xffffffff)
    elif name == 'truncated':
        del data[-1]
    else:
        raise ValueError(name)
    return bytes(data)


MUTATIONS = ('unsupported-codec', 'encrypted-codec', 'fragmented', 'encrypted-samples',
             'nonidentity-edit', 'composition-offset', 'huge-stts-count', 'huge-sample-count',
             'sample-count-mismatch', 'outside-mdat', 'past-file-offset', 'zero-first-chunk',
             'bad-sync-index', 'description-count-mismatch', 'external-data-reference',
             'zero-timescale', 'duplicate-stts', 'overlapping-chunks', 'oversized-moov', 'truncated')


def generate(destination):
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=160x120:rate=25',
                    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '3',
                    '-c:v', 'libx264', '-bf', '0', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
                    '-use_editlist', '0', str(destination)], check=True, timeout=60)


class MutationFixtureTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('ffmpeg'), 'ffmpeg required to generate independent fixture')
    def test_every_mutation_changes_independent_source(self):
        with tempfile.TemporaryDirectory() as td:
            source = pathlib.Path(td) / 'source.mp4'
            generate(source)
            original = source.read_bytes()
            self.assertGreater(path(original, b'moov')[-1][0], path(original, b'mdat')[-1][0])
            for name in MUTATIONS:
                with self.subTest(name=name):
                    changed = mutate(original, name)
                    self.assertNotEqual(changed, original)
                    self.assertEqual(source.read_bytes(), original)


@unittest.skipUnless(platform.system() == 'Darwin' and shutil.which('ffmpeg') and shutil.which('ffprobe'),
                     'requires macOS Swift/AVFoundation and independent FFmpeg')
class NativeSampleTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = pathlib.Path(cls.temp.name)
        cls.binary = cls.root / 'export-probe'
        sources = ['VoiceMatrix/MP4SampleTable.swift', 'VoiceMatrix/MatroskaWriter.swift',
                   'VoiceMatrix/LocalMKVExport.swift', 'probes/mkv-export/main.swift']
        subprocess.run(['swiftc', '-parse-as-library', *[str(ROOT / p) for p in sources],
                        '-o', str(cls.binary)], check=True, timeout=180)
        cls.source = cls.root / 'source.mp4'
        generate(cls.source)
        cls.original = cls.source.read_bytes()

    def test_real_packet_payloads_are_identical(self):
        output = self.root / 'valid.mkv'
        subprocess.run([str(self.binary), str(self.source), str(output)], check=True, timeout=90)
        self.assertEqual(output.read_bytes()[:4], bytes.fromhex('1a45dfa3'))
        def packets(file, selector):
            result = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', selector,
                '-show_packets', '-show_data_hash', 'sha256', '-show_entries', 'packet=size,data_hash,pts_time,dts_time,duration_time',
                '-of', 'json', str(file)], timeout=60))
            return result['packets']
        for selector in ('v:0', 'a:0'):
            with self.subTest(selector=selector):
                expected = packets(self.source, selector)
                self.assertTrue(expected)
                actual = packets(output, selector)
                self.assertEqual(len(expected), len(actual))
                for number, (before, after) in enumerate(zip(expected, actual)):
                    with self.subTest(packet=number):
                        self.assertEqual(int(before['size']), int(after['size']))
                        self.assertEqual(before['data_hash'], after['data_hash'])
                        for field in ('pts_time', 'duration_time'):
                            self.assertIn(field, before)
                            self.assertIn(field, after)
                            self.assertLessEqual(abs(float(before[field]) - float(after[field])), 0.001001)
                        # Demuxers may omit derived DTS; when exposed, it must agree too.
                        if 'dts_time' in before and 'dts_time' in after:
                            self.assertLessEqual(abs(float(before['dts_time']) - float(after['dts_time'])), 0.001001)
        self.assertEqual(self.original, self.source.read_bytes())

    def test_hostile_sample_tables_reject_without_output_or_mutation(self):
        for name in MUTATIONS:
            with self.subTest(mutation=name):
                folder = self.root / name
                folder.mkdir()
                source, output = folder / 'source.mp4', folder / 'output.mkv'
                mutated = mutate(self.original, name)
                source.write_bytes(mutated)
                before = hashlib.sha256(mutated).digest()
                result = subprocess.run([str(self.binary), str(source), str(output)], capture_output=True,
                                        text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0, f'{name} unexpectedly exported')
                # A Swift thrown rejection is expected. Memory faults are not safe rejections.
                self.assertNotIn(result.returncode, (-11, -10, -9), result.stderr[-3000:])
                self.assertTrue(result.returncode > 0 or 'Error raised at top level:' in result.stderr,
                                'Process crashed without throwing a rejection: ' + result.stderr[-3000:])
                self.assertFalse(output.exists(), result.stderr[-3000:])
                self.assertFalse(list(folder.glob('.mkv-export-*')))
                self.assertEqual(before, hashlib.sha256(source.read_bytes()).digest())
                self.assertEqual(self.original, self.source.read_bytes())
