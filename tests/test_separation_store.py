import pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SeparationStoreTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc') and __import__('sys').platform=='darwin','Native Swift CryptoKit required')
    def test_pair_validation_and_corruption(self):
        with tempfile.TemporaryDirectory() as td:
            binary=str(pathlib.Path(td)/'probe')
            subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/RetainedMediaReader.swift'),str(ROOT/'VoiceMatrix/VocalSeparationAssets.swift'),str(ROOT/'VoiceMatrix/SeparationStore.swift'),str(ROOT/'probes/separation-store/main.swift'),'-o',binary],check=True)
            subprocess.run([binary,str(pathlib.Path(td)/'store')],check=True,timeout=30)

class SeparationSurfaceTests(unittest.TestCase):
    def test_explicit_bounded_standalone_surface(self):
        view=(ROOT/'VoiceMatrix/VocalSeparationView.swift').read_text()
        importer=(ROOT/'VoiceMatrix/SeparationAudioImport.swift').read_text()
        self.assertIn('source.length)/rate<=10',importer)
        self.assertIn('left.count==expected',importer)
        self.assertIn('converter.primeMethod = .normal',importer)
        self.assertNotIn('converter.primeMethod = .none',importer)
        self.assertIn('let remaining=source.length-consumed',importer)
        self.assertLess(importer.index('guard remaining>0'),importer.index('try source.read'))
        self.assertIn('channels==1 ? 0:1',importer)
        self.assertIn('withTaskCancellationHandler',view)
        self.assertIn('audio.releaseProcessing(lease)',view)
        self.assertIn('await engine.close()',view)
        self.assertNotIn('URLSession',view)
        self.assertNotIn('VideoQueue',view)
        self.assertIn('Both stems use the same gain',view)
        probe=(ROOT/'probes/separation-import/main.swift').read_text()
        self.assertIn('settings:disk.settings,commonFormat:.pcmFormatFloat32,interleaved:false',probe)
        self.assertIn('FAIL separation import probe:',probe)
        self.assertIn('stage("resampled decode")',probe)
        self.assertIn('file.processingFormat.channelCount==3 && file.length==4410',probe)
        self.assertIn('catch SeparationStore.Failure.invalid',probe)

class SeparationImportTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc') and __import__('sys').platform=='darwin','Apple audio framework required')
    def test_native_audio_import(self):
        with tempfile.TemporaryDirectory() as td:
            binary=str(pathlib.Path(td)/'probe')
            subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/RetainedMediaReader.swift'),str(ROOT/'VoiceMatrix/VocalSeparationAssets.swift'),str(ROOT/'VoiceMatrix/SeparationStore.swift'),str(ROOT/'VoiceMatrix/SeparationAudioImport.swift'),str(ROOT/'probes/separation-import/main.swift'),'-o',binary],check=True)
            subprocess.run([binary,str(pathlib.Path(td)/'audio')],check=True,timeout=60)

class SeparationWorkflowTests(unittest.TestCase):
    def test_native_and_ui_gates_include_feature_without_extra_batch(self):
        ui=(ROOT/'.github/workflows/character-ui-smoke.yml').read_text()
        runs=[line for line in ui.splitlines() if 'xcodebuild test-without-building ' in line]
        self.assertEqual(len(runs),4)
        self.assertIn('-only-testing:VoiceMatrixUITests/VocalSeparationUITests',runs[0])
        build=next(line for line in ui.splitlines() if 'xcodebuild build-for-testing ' in line)
        self.assertIn('-only-testing:VoiceMatrixUITests/VocalSeparationUITests',build)
        self.assertNotIn('prepare_vocal_separation.py',ui)
        native=(ROOT/'.github/workflows/vocal-separation-native.yml').read_text()
        self.assertIn('tests.test_separation_store',native)
        self.assertIn("'probes/separation-import/**'",native)
