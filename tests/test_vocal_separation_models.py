import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ModelPreparationTests(unittest.TestCase):
 def test_pinned_preparer_exists(self):
  self.assertTrue((ROOT/'tools/prepare_vocal_separation.py').is_file())
 def test_native_engine_exists(self):
  self.assertTrue((ROOT/'VoiceMatrix/VocalSeparationEngine.swift').is_file())

class PreparationSafetyTests(unittest.TestCase):
 def test_changed_model_and_link_rejected(self):
  import tempfile,hashlib
  from unittest import mock
  from tools import prepare_vocal_separation as p
  with tempfile.TemporaryDirectory() as td:
   root=pathlib.Path(td);data=b'known test bytes';file=root/'vocals.onnx';file.write_bytes(data)
   with mock.patch.object(p,'MODELS',{'vocals.onnx':(len(data),hashlib.sha256(data).hexdigest())}):
    p.validate(root);file.write_bytes(b'x'*len(data))
    with self.assertRaises(ValueError):p.validate(root)
    file.unlink();file.symlink_to(root/'missing')
    with self.assertRaises(ValueError):p.validate(root)
 def test_tar_inventory_rejected_without_output(self):
  import tempfile,tarfile,hashlib,io
  from unittest import mock
  from tools import prepare_vocal_separation as p
  with tempfile.TemporaryDirectory() as td:
   root=pathlib.Path(td);archive=root/'bad.tar.bz2'
   with tarfile.open(archive,'w:bz2') as t:
    member=tarfile.TarInfo('../escape');member.size=3;t.addfile(member,io.BytesIO(b'bad'))
   with mock.patch.object(p,'ARCHIVE_BYTES',archive.stat().st_size),mock.patch.object(p,'ARCHIVE_SHA',hashlib.sha256(archive.read_bytes()).hexdigest()):
    with self.assertRaises(ValueError):p.prepare(root/'output',archive)
   self.assertFalse((root/'output').exists());self.assertFalse((root/'escape').exists())
 def test_manifest_records_fixed_44100_contract_and_original_hashes(self):
  from tools import prepare_vocal_separation as p
  self.assertEqual(p.PROVENANCE['sampleRate'],44100)
  self.assertIn('41000',p.PROVENANCE['metadataNotice'])
  self.assertEqual(p.ARCHIVE_BYTES,74682545)
  self.assertEqual(set(p.MODELS),{'vocals.onnx','accompaniment.onnx'})
 def test_native_harness_uses_actual_models_and_fixed_reference(self):
  text=(ROOT/'probes/vocal-separation-native/Checks.swift').read_text()
  self.assertIn('VocalSeparationEngine(modelRoot:',text)
  self.assertIn('engine.separate(left:left,right:right)',text)
  self.assertIn('beforeError*0.8',text)
  self.assertIn('XCTAssertLessThan(maximum,0.002)',text)

class SeparationLicenseTests(unittest.TestCase):
 def test_pack_notices_include_weight_and_conversion_licenses(self):
  from tools import prepare_vocal_separation as p
  self.assertTrue(hasattr(p,'pack_notices'),'Model bundle lacks combined weight/conversion license staging')
  notices=p.pack_notices()
  self.assertIn('MIT License',notices['LICENSES.txt'])
  self.assertIn('Deezer SA.',notices['LICENSES.txt'])
  self.assertIn('Apache License',notices['LICENSES.txt'])
  self.assertIn('TERMS AND CONDITIONS',notices['LICENSES.txt'])
  self.assertIn('Xiaomi',notices['NOTICE.txt'])
  self.assertIn('Fangjun Kuang',notices['NOTICE.txt'])
  self.assertIn('10.21105/joss.02154',notices['NOTICE.txt'])

class SimulatorSelectionTests(unittest.TestCase):
 def test_harness_uses_supported_modern_device(self):
  workflow=(ROOT/'.github/workflows/vocal-separation-native.yml').read_text()
  self.assertIn("device='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus'",workflow)
  self.assertNotIn('reversed(types)',workflow)
