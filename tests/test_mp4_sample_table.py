import json, pathlib, platform, shutil, subprocess, tempfile, unittest, struct
ROOT=pathlib.Path(__file__).resolve().parents[1]
class MP4TableTests(unittest.TestCase):
 def test_native_reader_exists(self):
  self.assertTrue((ROOT/'VoiceMatrix/MP4SampleTable.swift').is_file())
 @unittest.skipUnless(shutil.which('swiftc') and shutil.which('ffmpeg'), 'requires native Swift and ffmpeg')
 def test_real_packet_tables_and_hostile_offsets(self):
  with tempfile.TemporaryDirectory() as td:
   d=pathlib.Path(td); binary=d/'probe'; source=d/'input.mp4'
   subprocess.run(['swiftc','-parse-as-library',str(ROOT/'VoiceMatrix/MP4SampleTable.swift'),str(ROOT/'probes/mp4-sample-table/main.swift'),'-o',str(binary)],check=True)
   subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=160x120:rate=25','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','3','-c:v','libx264','-bf','0','-pix_fmt','yuv420p','-c:a','aac','-use_editlist','0',str(source)],check=True)
   original=source.read_bytes(); actual=json.loads(subprocess.check_output([str(binary),str(source)]))
   for ti,spec in enumerate(['v:0','a:0']):
    packets=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams',spec,'-show_packets','-of','json',str(source)]))['packets']
    self.assertEqual(len(actual[ti]['packets']),len(packets))
    for a,p in zip(actual[ti]['packets'],packets):
     self.assertEqual(a['offset'],int(p['pos']));self.assertEqual(a['size'],int(p['size']))
     self.assertAlmostEqual(a['pts'],float(p['pts_time']),places=5);self.assertAlmostEqual(a['duration'],float(p['duration_time']),places=5)
   self.assertEqual(source.read_bytes(),original)
   # Conventional mp4a header channelCount=2 must not override mono ASC.
   conventional=d/'header-two.mp4'; b=bytearray(original); idx=b.index(b'mp4a'); b[idx+20:idx+22]=struct.pack('>H',2);conventional.write_bytes(b)
   headerResult=json.loads(subprocess.check_output([str(binary),str(conventional)]));self.assertEqual(headerResult[1]['channels'],1)
   for name,typ,offset,value in [('table-count',b'stsz',12,0xffffffff),('chunk-count',b'stsc',12,0xffffffff),('external',b'url ',4,0),('duration',b'stts',16,0xffffffff)]:
    bad=d/(name+'.mp4'); b=bytearray(original);idx=b.index(typ);b[idx+offset:idx+offset+4]=struct.pack('>I',value);bad.write_bytes(b)
    self.assertNotEqual(subprocess.run([str(binary),str(bad)],capture_output=True).returncode,0,name)
   roll=d/'roll.mp4';b=bytearray(original);idx=b.index(b'sgpd');b[idx+20:idx+22]=struct.pack('>H',0xfffe);roll.write_bytes(b);self.assertNotEqual(subprocess.run([str(binary),str(roll)],capture_output=True).returncode,0)
   fragmented=d/'fragment.mp4';fragmented.write_bytes(original+struct.pack('>I4s',8,b'moof'));self.assertNotEqual(subprocess.run([str(binary),str(fragmented)],capture_output=True).returncode,0)

   bad=d/'offset.mp4'; b=bytearray(original); idx=b.index(b'stco'); b[idx+12:idx+16]=struct.pack('>I',0xffffffff);bad.write_bytes(b)
   self.assertNotEqual(subprocess.run([str(binary),str(bad)],capture_output=True).returncode,0)
   link=d/'link.mp4';link.symlink_to(source);self.assertNotEqual(subprocess.run([str(binary),str(link)],capture_output=True).returncode,0)
   mutable=d/'mutable.mp4';mutable.write_bytes(original);self.assertNotEqual(subprocess.run([str(binary),str(mutable),'mutation'],capture_output=True).returncode,0)
