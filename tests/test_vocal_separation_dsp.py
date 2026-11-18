"""Native DSP convention checks only; actual trained-model parity is a separate gate."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[1]

class DSPSourceTests(unittest.TestCase):
    def test_production_dsp_present(self):
        self.assertTrue((ROOT/'VoiceMatrix/VocalSeparationDSP.swift').is_file())

@unittest.skipUnless(shutil.which('swiftc'),'native Swift compiler unavailable')
class NativeDSPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.temp.cleanup)
        cls.binary=Path(cls.temp.name)/'dsp'
        subprocess.run(['swiftc','-O','-parse-as-library',str(ROOT/'VoiceMatrix/VocalSeparationDSP.swift'),str(ROOT/'probes/vocal-separation-dsp/main.swift'),'-o',str(cls.binary)],check=True,timeout=120)
    def run_probe(self,*args):
        subprocess.run([str(self.binary),*map(str,args)],check=True,timeout=90,capture_output=True,text=True)
    def test_bounds_finiteness_and_cancel(self):self.run_probe('checks')
    def test_preparation_and_reconstruction_match_independent_numpy(self):
        with tempfile.TemporaryDirectory() as td:
            d=Path(td);n=8001;t=np.arange(n)/44100
            channels=[(.2*np.sin(2*np.pi*443*t)).astype('float32'),(.13*np.cos(2*np.pi*997*t)).astype('float32')]
            channels[0][0]=.7;channels[0][-1]=-.6
            channels[1][0]=-.4;channels[1][-1]=.5
            for name,x in zip(['left','right'],channels):x.astype('<f4').tofile(d/(name+'.f32'))
            self.run_probe('prepare',d/'left.f32',d/'right.f32',d/'mag.f32',d/'meta.json')
            window=.5-.5*np.cos(2*np.pi*np.arange(4096)/4096)
            padded=n+8192;count=1+(padded-4096+1023)//1024;length=4096+(count-1)*1024
            spectra=[];expected=np.zeros((2,512,1024),dtype='float32')
            for channel,x in enumerate(channels):
                values=np.zeros(length);values[4096:4096+n]=x
                frames=np.stack([values[i*1024:i*1024+4096]*window for i in range(count)])
                spec=np.fft.rfft(frames);spectra.append(spec)
                expected[channel,:count]=np.abs(spec[:,:1024])
            actual=np.fromfile(d/'mag.f32',dtype='<f4').reshape(2,512,1024)
            np.testing.assert_allclose(actual,expected,atol=3e-5,rtol=2e-6)
            self.assertEqual(json.loads((d/'meta.json').read_text())['originalFrames'],n)
            # Deliberately supplied mathematical masks test DSP, not source separation.
            vocals=np.full(expected.shape,.3,dtype='float32');accomp=np.full(expected.shape,.8,dtype='float32')
            vocals.tofile(d/'v.f32');accomp.tofile(d/'a.f32')
            self.run_probe('reconstruct',d/'left.f32',d/'right.f32',d/'v.f32',d/'a.f32',d/'out')
            denominator=np.zeros(length)
            for frame in range(count):denominator[frame*1024:frame*1024+4096]+=window**2
            for label,pred in [('vocals',vocals),('accompaniment',accomp)]:
                mask=(pred.astype('float64')**2+5e-11)/(vocals.astype('float64')**2+accomp.astype('float64')**2+1e-10)
                for channel,side in enumerate(['left','right']):
                    transformed=np.zeros_like(spectra[channel]);transformed[:,:1024]=spectra[channel][:,:1024]*mask[channel,:count]
                    frames=np.fft.irfft(transformed,n=4096);result=np.zeros(length)
                    for frame in range(count):result[frame*1024:frame*1024+4096]+=frames[frame]*window
                    np.divide(result,denominator,out=result,where=denominator>0)
                    restored=np.fromfile(d/f'out-{label}-{side}.f32',dtype='<f4')
                    self.assertEqual(len(restored),n)
                    np.testing.assert_allclose(restored,result[4096:4096+n],atol=2e-6,rtol=2e-5)
