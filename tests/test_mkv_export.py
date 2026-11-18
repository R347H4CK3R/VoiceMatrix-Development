"""Real native remux and independent decoder checks; macOS required, never emulate AVFoundation."""
import hashlib
import json
import pathlib
import platform
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class MKVExportTests(unittest.TestCase):
    def test_native_implementation_present(self):
        self.assertTrue((ROOT / 'VoiceMatrix/LocalMKVExport.swift').is_file())
        self.assertTrue((ROOT / 'VoiceMatrix/MatroskaWriter.swift').is_file())

    @unittest.skipUnless(platform.system() == 'Darwin' and shutil.which('ffmpeg'), 'requires macOS AVFoundation + ffmpeg')
    def test_real_remux_and_failure_preservation(self):
        with tempfile.TemporaryDirectory() as td:
            d = pathlib.Path(td)
            binary, source, dest = d/'probe', d/'input.mp4', d/'output.mkv'
            subprocess.run(['swiftc', '-parse-as-library', str(ROOT/'VoiceMatrix/MP4SampleTable.swift'), str(ROOT/'VoiceMatrix/MatroskaWriter.swift'), str(ROOT/'VoiceMatrix/LocalMKVExport.swift'), str(ROOT/'probes/mkv-export/main.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary), '--aac-policy'], check=True)
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=160x120:rate=25','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','3','-c:v','libx264','-bf','0','-pix_fmt','yuv420p','-c:a','aac','-use_editlist','0',str(source)],check=True)
            original = source.read_bytes()
            subprocess.run([str(binary),str(source),str(dest)],check=True)
            self.assertEqual(dest.read_bytes()[:4], bytes.fromhex('1a45dfa3'))
            info = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(dest)]))
            self.assertEqual([s['codec_name'] for s in info['streams']], ['h264','aac'])
            self.assertLess(abs(float(info['format']['duration']) - 3), 0.1)
            # Decode the exported frames and compare payload, not container/PTS text.
            for spec, fmt, codec in [('0:v:0','rawvideo','rawvideo'),('0:a:0','s16le','pcm_s16le')]:
                def decode(p):
                    return subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-map',spec,'-f',fmt,'-c',codec,'-'])
                originalDecoded, exportedDecoded = decode(source), decode(dest)
                if originalDecoded != exportedDecoded:
                    evidence = ROOT/'mkv-native-diagnostics'
                    evidence.mkdir(exist_ok=True)
                    shutil.copyfile(source,evidence/'source.mp4')
                    shutil.copyfile(dest,evidence/'export.mkv')
                    print('DECODE_MISMATCH',spec,'sourceBytes',len(originalDecoded),'exportBytes',len(exportedDecoded),flush=True)
                    for item in [source,dest]:
                        print('STREAM_METADATA',item.suffix,subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(item)]).decode(),flush=True)
                self.assertEqual(hashlib.sha256(originalDecoded).digest(),hashlib.sha256(exportedDecoded).digest(),spec)
            self.assertEqual(original,source.read_bytes())
            saved = dest.read_bytes()
            self.assertNotEqual(subprocess.run([str(binary),str(source),str(dest)],capture_output=True).returncode,0)
            self.assertEqual(saved,dest.read_bytes())
            bad = d/'bframes.mp4'
            subprocess.run(['ffmpeg','-v','error','-i',str(source),'-c:v','libx264','-bf','3','-c:a','copy',str(bad)],check=True)
            self.assertNotEqual(subprocess.run([str(binary),str(bad),str(d/'bad.mkv')],capture_output=True).returncode,0)
            self.assertFalse((d/'bad.mkv').exists())

            self.assertNotEqual(subprocess.run([str(binary),str(source),str(d/'tiny.mkv'),'100'],capture_output=True).returncode,0)
            self.assertFalse((d/'tiny.mkv').exists())
            self.assertEqual(original,source.read_bytes())
            self.assertFalse(list(d.glob('.mkv-export-*')))

            self.assertNotEqual(subprocess.run([str(binary),str(source),str(d/'cancel.mkv'),'cancel'],capture_output=True).returncode,0)
            self.assertFalse((d/'cancel.mkv').exists())
            self.assertEqual(original,source.read_bytes())
