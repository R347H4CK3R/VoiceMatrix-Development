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
   self.assertTrue(all(p['discardPaddingNanoseconds']==0 for p in actual[0]['packets']))
   self.assertTrue(all(p['discardPaddingNanoseconds']==0 for p in actual[1]['packets'][:-1]))
   self.assertEqual(actual[1]['packets'][-1]['discardPaddingNanoseconds'],8_000_000)
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
 @unittest.skipUnless(shutil.which('swiftc') and shutil.which('ffmpeg'), 'requires native Swift and ffmpeg')
 def test_aac_final_packet_padding_and_short_middle_rejection(self):
  with tempfile.TemporaryDirectory() as td:
   d=pathlib.Path(td); source=d/'input.mp4'; binary=d/'padding'; probe=d/'Padding.swift'
   probe.write_text('''import Foundation
@main struct Check {
 static func main() throws {
  let table=try MP4SampleTable(url:URL(fileURLWithPath:CommandLine.arguments[1]))
  if CommandLine.arguments.last == "parse-only" { print("PARSER_ACCEPTED"); return }
  precondition(table.video.samples.allSatisfy { $0.discardPaddingNanoseconds==0 })
  precondition(table.audio.samples.dropLast().allSatisfy { $0.discardPaddingNanoseconds==0 })
  let expected:UInt64 = CommandLine.arguments.last == "full-tail" ? 0:8_000_000
  precondition(table.audio.samples.last!.discardPaddingNanoseconds==expected)
  print("AAC_TAIL_PADDING_8MS_VERIFIED")
 }
}
''')
   subprocess.run(['swiftc','-parse-as-library',str(ROOT/'VoiceMatrix/MP4SampleTable.swift'),str(probe),'-o',str(binary)],check=True)
   subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=160x120:rate=25','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','3','-c:v','libx264','-bf','0','-pix_fmt','yuv420p','-c:a','aac','-use_editlist','0',str(source)],check=True)
   self.assertIn(b'AAC_TAIL_PADDING_8MS_VERIFIED',subprocess.check_output([str(binary),str(source)]))
   original=source.read_bytes(); b=bytearray(original)
   def boxes(start,end):
    p=start
    while p<end:
     size=struct.unpack_from('>I',b,p)[0]; self.assertGreaterEqual(size,8); self.assertLessEqual(p+size,end)
     yield bytes(b[p+4:p+8]),p,p+size
     p+=size
   moov=next(x for x in boxes(0,len(b)) if x[0]==b'moov')
   for _,ts,te in (x for x in boxes(moov[1]+8,moov[2]) if x[0]==b'trak'):
    mdia=next(x for x in boxes(ts+8,te) if x[0]==b'mdia')
    children=list(boxes(mdia[1]+8,mdia[2]));hdlr=next(x for x in children if x[0]==b'hdlr')
    if b[hdlr[1]+16:hdlr[1]+20]!=b'soun': continue
    minf=next(x for x in children if x[0]==b'minf');stbl=next(x for x in boxes(minf[1]+8,minf[2]) if x[0]==b'stbl')
    stts=next(x for x in boxes(stbl[1]+8,stbl[2]) if x[0]==b'stts');p=stts[1]
    self.assertEqual(struct.unpack_from('>I',b,p+12)[0],2)
    n,delta,lastn,lastdelta=struct.unpack_from('>IIII',b,p+16)
    self.assertEqual((delta,lastn,lastdelta),(1024,1,640))
    full=bytearray(original);struct.pack_into('>I',full,p+28,1024)
    mdhd=next(x for x in children if x[0]==b'mdhd');self.assertEqual(full[mdhd[1]+8],0)
    duration=struct.unpack_from('>I',full,mdhd[1]+24)[0];struct.pack_into('>I',full,mdhd[1]+24,duration+384)
    fulltail=d/'full-tail.mp4';fulltail.write_bytes(full);subprocess.run([str(binary),str(fulltail),'full-tail'],check=True)
    before=n*delta+lastdelta
    # Keep exact mdhd/stts total duration, but introduce an illegal short interior packet.
    struct.pack_into('>I',b,p+20,delta-1);struct.pack_into('>I',b,p+28,lastdelta+n)
    self.assertEqual(n*(delta-1)+lastdelta+n,before)
   bad=d/'short-middle.mp4';bad.write_bytes(b)
   self.assertNotEqual(subprocess.run([str(binary),str(bad),'parse-only'],capture_output=True).returncode,0)
   self.assertEqual(source.read_bytes(),original)
