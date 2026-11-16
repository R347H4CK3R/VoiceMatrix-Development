import importlib.util,pathlib,sys,unittest,tempfile,wave
ROOT=pathlib.Path(__file__).resolve().parents[1];P=ROOT/'probes/overlap-stress';sys.path.insert(0,str(P))
from prepare import mix,read_pcm
from measure import measure_window
class MixingTests(unittest.TestCase):
 def test_exact_sum_and_offsets(self):
  out,parts=mix([100,-100,0],[200,-200],2)
  self.assertEqual(list(out),[50,-50,100,-100]);self.assertEqual(list(parts[1]),[0,0,100,-100])
 def test_full_scale_no_clipping(self):
  out,_=mix([32767,-32768],[32767,-32768],0);self.assertEqual(list(out),[32766,-32768])
 def test_quieter_track_ratio(self):
  out,parts=mix([800]*16000,[800]*16000,0,.125);m=measure_window(*parts,0,1)
  self.assertAlmostEqual(m['trackEnergyFractions'][1],1/17);self.assertEqual(m['bothTracksNonzeroSeconds'],1)
 def test_single_preserves_length_and_no_second_energy(self):
  out,parts=mix([100]*16000,[200]*32000,0,0);self.assertEqual(len(out),16000);self.assertEqual(measure_window(*parts,0,1)['trackEnergyFractions'],[1,0])
 def test_sequential_has_no_simultaneous_samples(self):
  out,parts=mix([100]*16000,[200]*16000,16000);self.assertEqual(measure_window(*parts,0,2)['bothTracksNonzeroSeconds'],0)
 def test_invalid_crops_rejected(self):
  for a,b in [(-1,1),(0,2),(1,1),(0,float('nan'))]:
   with self.assertRaises(ValueError):measure_window([1]*16000,[1]*16000,a,b)

class SourceReadTests(unittest.TestCase):
 def test_truncated_wave_is_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'x.wav'
   with wave.open(str(p),'wb') as w:w.setparams((1,2,16000,0,'NONE','none'));w.writeframes(b'\0\0'*100)
   p.write_bytes(p.read_bytes()[:-2])
   with self.assertRaises(ValueError):read_pcm(p)
