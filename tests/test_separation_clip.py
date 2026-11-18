"""Actual AVFoundation clip extraction, not mocked decoding or speaker inference."""
from pathlib import Path
import hashlib
import json
import platform
import shutil
import struct
import subprocess
import tempfile
import unittest
import wave

ROOT=Path(__file__).resolve().parents[1]

class ClipSourceTests(unittest.TestCase):
    def test_extractor_is_present(self):
        self.assertTrue((ROOT/'VoiceMatrix/SeparationClipExtractor.swift').is_file())

@unittest.skipUnless(platform.system()=='Darwin','requires native macOS AVFoundation')
class NativeClipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.temp.cleanup)
        cls.root=Path(cls.temp.name);cls.exe=cls.root/'clip'
        subprocess.run(['swiftc','-O','-parse-as-library',*[str(ROOT/'VoiceMatrix'/name) for name in ['RetainedMediaReader.swift','VocalSeparationAssets.swift','SeparationStore.swift','SeparationClipExtractor.swift','SeparationClipHandoff.swift']],str(ROOT/'probes/separation-clip/main.swift'),'-o',str(cls.exe)],check=True,timeout=120)
        if not shutil.which('ffmpeg'):raise RuntimeError('ffmpeg fixture tool required')
        cls.wav=cls.root/'stereo.wav'
        with wave.open(str(cls.wav),'wb') as w:
            w.setparams((2,2,44100,0,'NONE','not compressed'))
            w.writeframes(b''.join(struct.pack('<hh',5000+(i%101),-9000-(i%73)) for i in range(44100*2)))
        cls.mono=cls.root/'mono.wav'
        with wave.open(str(cls.mono),'wb') as w:
            w.setparams((1,2,48000,0,'NONE','not compressed'));w.writeframes(struct.pack('<h',4000)*96000)
        cls.surround=cls.root/'surround.wav'
        with wave.open(str(cls.surround),'wb') as w:
            w.setparams((6,2,44100,0,'NONE','not compressed'));w.writeframes(struct.pack('<hhhhhh',1,2,3,4,5,6)*44100)
        cls.low_rate=cls.root/'low-rate.wav';cls.high_rate=cls.root/'high-rate.wav'
        for file,rate in [(cls.low_rate,4000),(cls.high_rate,384000)]:
            with wave.open(str(file),'wb') as w:
                w.setparams((1,2,rate,0,'NONE','not compressed'));w.writeframes(struct.pack('<h',1000)*rate)
        cls.video=cls.root/'video.mov';cls.offset=cls.root/'offset.mov';cls.multi=cls.root/'multi.mov'
        cls.aac=cls.root/'url-aac.mp4';cls.ten=cls.root/'ten-seconds.wav'
        with wave.open(str(cls.ten),'wb') as w:
            w.setparams((2,2,44100,0,'NONE','not compressed'));w.writeframes(struct.pack('<hh',5000,-9000)*441000)
        common=['ffmpeg','-v','error','-y']
        subprocess.run(common+['-f','lavfi','-i','color=c=black:s=64x64:d=2','-i',str(cls.wav),'-map','0:v','-map','1:a','-c:v','mpeg4','-c:a','pcm_s16le',str(cls.video)],check=True,timeout=60)
        subprocess.run(common+['-f','lavfi','-i','color=c=black:s=64x64:d=3','-itsoffset','0.25','-i',str(cls.wav),'-map','0:v','-map','1:a','-c:v','mpeg4','-c:a','pcm_s16le',str(cls.offset)],check=True,timeout=60)
        subprocess.run(common+['-f','lavfi','-i','color=c=black:s=64x64:d=2','-i',str(cls.wav),'-map','0:v','-map','1:a','-c:v','mpeg4','-c:a','aac','-b:a','192k','-movflags','+faststart',str(cls.aac)],check=True,timeout=60)
        subprocess.run(common+['-i',str(cls.wav),'-i',str(cls.wav),'-map','0:a','-map','1:a','-c:a','pcm_s16le',str(cls.multi)],check=True,timeout=60)
    def extract(self,source,start,duration,success=True,mode='extract'):
        before=hashlib.sha256(source.read_bytes()).hexdigest()
        output=self.root/('samples-'+next(tempfile._get_candidate_names())+'.f32')
        result=subprocess.run([str(self.exe),mode,str(source),str(start),str(duration),str(output)],capture_output=True,text=True,timeout=45)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),before,'Extraction modified original')
        if success:
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            info=json.loads(result.stdout);values=list(struct.unpack('<'+'f'*(output.stat().st_size//4),output.read_bytes()))
            self.assertEqual(len(values),info['frames']*2)
            return info,values
        self.assertNotEqual(result.returncode,0,'Invalid clip was accepted')
        self.assertFalse(output.exists(),'Rejected clip published output')
    def test_stereo_nonzero_start_exact_frames_and_source_retained(self):
        info,values=self.extract(self.wav,.5,.5)
        self.assertEqual(info['frames'],22050)
        self.assertEqual(info['sampleRate'],44100)
        with wave.open(str(self.wav),'rb') as w:w.setpos(22050);expected=struct.unpack('<'+'h'*(22050*2),w.readframes(22050))
        self.assertLess(max(abs(a-b/32768) for a,b in zip(values,expected)),1e-6)
        self.assertGreater(values[0],0);self.assertLess(values[1],0)
    def test_mono_resample_is_explicitly_duplicated(self):
        info,values=self.extract(self.mono,.25,.75)
        self.assertLessEqual(abs(info['frames']-33075),1)
        self.assertEqual(values[::2],values[1::2])
        self.assertGreater(sum(values)/len(values),.1)
    def test_video_audio_matches_retained_pcm(self):
        _,actual=self.extract(self.video,.5,.5)
        _,expected=self.extract(self.wav,.5,.5)
        self.assertEqual(actual,expected)
    def test_invalid_bounds_tracks_channels_and_initial_gap_rejected(self):
        for source,start,duration in [(self.wav,-1,1),(self.wav,0,.49),(self.wav,0,10.01),(self.wav,1.75,.5),(self.wav,float('nan'),1),(self.multi,0,1),(self.surround,0,1),(self.offset,0,1),(self.offset,2.4,.5),(self.low_rate,0,.5),(self.high_rate,0,.5)]:
            with self.subTest(source=source.name,start=start,duration=duration):self.extract(source,start,duration,False)
    def test_selected_interval_after_initial_edit_is_allowed(self):
        info,_=self.extract(self.offset,.5,.5)
        self.assertLessEqual(abs(info['frames']-22050),1)
    def test_cancellation_never_publishes_output(self):
        self.extract(self.wav,0,1,False,'cancel')

    def test_private_handoff_preserves_original_and_binds_published_clip(self):
        for mode in ['handoff-good','handoff-wrong-sha','handoff-corrupt-clip','handoff-corrupt-receipt','handoff-cancel']:
            with self.subTest(mode=mode):
                before=hashlib.sha256(self.wav.read_bytes()).hexdigest()
                store=self.root/('store-'+next(tempfile._get_candidate_names()))
                result=subprocess.run([str(self.exe),mode,str(self.wav),'0.25','0.5',str(store)],capture_output=True,text=True,timeout=60)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(hashlib.sha256(self.wav.read_bytes()).hexdigest(),before)
                info=json.loads(result.stdout)
                self.assertTrue(info['checked'])
                self.assertEqual(info['clips'],0 if mode in ['handoff-wrong-sha','handoff-cancel'] else 1)

    def test_real_aac_offset_matches_same_decoder_whole_slice(self):
        full,whole=self.extract(self.aac,0,2)
        clip,selected=self.extract(self.aac,.5,.5)
        self.assertLessEqual(abs(full['frames']-88200),1)
        self.assertLessEqual(abs(clip['frames']-22050),1)
        expected=whole[22050*2:22050*2+len(selected)]
        self.assertEqual(len(selected),len(expected))
        self.assertLess(max(abs(a-b) for a,b in zip(selected,expected)),3e-5,
                        'AAC seek/priming must match full decode, not shifted output')
    def test_exact_ten_second_limit_without_truncation(self):
        info,values=self.extract(self.ten,0,10)
        self.assertEqual(info['frames'],441000)
        self.assertEqual(len(values),882000)
        self.extract(self.ten,0,10.000001,False)

    def test_explicit_timeline_overlap_and_gap_policy(self):
        result=subprocess.run([str(self.exe),'timeline-checks',str(self.wav),'0','1',str(self.root/'unused')],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue(json.loads(result.stdout)['timelineChecked'])

    def test_crash_scratch_bounds_and_evidence_preservation(self):
        for mode in ['scratch-empty-repeat','scratch-sparse','scratch-stage-link','scratch-file-link','scratch-fifo','scratch-many-files','scratch-many-entries']:
            with self.subTest(mode=mode):
                before=hashlib.sha256(self.wav.read_bytes()).hexdigest()
                store=self.root/('scratch-store-'+next(tempfile._get_candidate_names()))
                result=subprocess.run([str(self.exe),mode,str(self.wav),'0.25','0.5',str(store)],capture_output=True,text=True,timeout=45 if mode=='scratch-empty-repeat' else 10)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertTrue(json.loads(result.stdout)['scratchChecked'])
                self.assertEqual(hashlib.sha256(self.wav.read_bytes()).hexdigest(),before)

    def test_resampled_full_endpoint_and_tail_match_full_decode(self):
        full,whole=self.extract(self.mono,0,2)
        tail,selected=self.extract(self.mono,1.25,.75)
        self.assertLessEqual(abs(full['frames']-88200),1)
        self.assertLessEqual(abs(tail['frames']-33075),1)
        expected=whole[55125*2:55125*2+len(selected)]
        self.assertEqual(len(selected),len(expected))
        self.assertLess(max(abs(a-b) for a,b in zip(selected,expected)),3e-5,
                        'Resampler tail must match full-source decoder state')
