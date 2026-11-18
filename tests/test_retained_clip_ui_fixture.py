import json,tempfile,unittest,struct
from pathlib import Path
from tools.seed_retained_clip_ui import seed,check,roots,sha,source_wave,VALID
ROOT=Path(__file__).resolve().parents[1]
class RetainedClipFixtureTests(unittest.TestCase):
 def test_only_exact_clip_and_unchanged_jobs_pass(self):
  with tempfile.TemporaryDirectory() as td:
   container=Path(td);seed(container);jobs,separation=roots(container)
   with self.assertRaises(FileExistsError):seed(container)
   with self.assertRaises(AssertionError):check(container)
   clip=separation/'Clip-test';clip.mkdir(parents=True)
   original=source_wave();pcm=struct.pack('<ff',.125,-.125)*66150
   data=original[:4]+struct.pack('<I',36+len(pcm))+original[8:40]+struct.pack('<I',len(pcm))+pcm
   (clip/'clip.wav').write_bytes(data)
   receipt=dict(sourceJobID=VALID,sourceSHA256=sha(original),requestedStart=1,requestedSeconds=1.5,actualStart=1,frames=66150,clipSHA256=sha(data))
   (clip/'receipt.json').write_text(json.dumps(receipt));check(container)
   (jobs/VALID.lower()/'source.wav').write_bytes(b'changed')
   with self.assertRaises(AssertionError):check(container)
 def test_seeded_ui_runs_only_in_existing_final_batch(self):
  source=(ROOT/'.github/workflows/character-ui-smoke.yml').read_text()
  runs=[x for x in source.splitlines() if 'xcodebuild test-without-building ' in x]
  self.assertEqual(len(runs),4)
  self.assertNotIn('RetainedClipUITests',runs[0])
  self.assertIn('-only-testing:VoiceMatrixUITests/RetainedClipUITests',runs[3])
