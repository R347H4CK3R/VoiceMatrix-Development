import importlib.util,pathlib,tempfile,unittest,uuid,shutil,sys,json,io
from contextlib import redirect_stdout
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('fixture',ROOT/'tools/speaker_handoff_fixture.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ContainerIdentity(unittest.TestCase):
 def test_relocation_is_bounded_and_preservation_still_enforced(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d).resolve(strict=True);sid=str(uuid.uuid4());base=root/'CoreSimulator/Devices'/sid/'data/Containers/Data/Application';old=base/str(uuid.uuid4());old.mkdir(parents=True)
   fixture=root/'fixture/Application Support'
   for name in ['LocalVideoStudio','CharacterReferences']:(fixture/name).mkdir(parents=True)
   (fixture/'LocalVideoStudio/reference.wav').write_bytes(b'synthetic');(fixture/'CharacterReferences/index.json').write_text('{}')
   receipt=root/'receipt.json'
   def run(container,verify=False,reported=None,simulator=sid):
    args=['fixture',str(container),str(fixture.parent),str(receipt),'--simulator-id',simulator]+(['--verify'] if verify else [])
    with patch.object(sys,'argv',args),patch.object(m.subprocess,'check_output',return_value=str(reported or container)+'\n') as query:
     m.main();query.assert_called_once_with(['xcrun','simctl','get_app_container',simulator,'com.voicematrix.app','data'],text=True)
   run(old)
   with self.assertRaises(AssertionError):run(old)
   new=base/str(uuid.uuid4());old.rename(new)
   output=io.StringIO()
   with redirect_stdout(output):run(new,True)
   proof=json.loads(output.getvalue())
   self.assertEqual(proof['identity'],{'simulatorRoot':str(base.parents[3]),'simulatorID':sid,'bundleID':'com.voicematrix.app'})
   self.assertEqual(proof['beforeContainer'],str(old));self.assertEqual(proof['afterContainer'],str(new))
   self.assertEqual(proof['verifiedFileCount'],2);self.assertIs(proof['noExtraMedia'],True)
   original=receipt.read_text();changed=json.loads(original);changed['identity']['bundleID']='com.other.app';receipt.write_text(json.dumps(changed))
   with self.assertRaises(AssertionError):run(new,True)
   receipt.write_text(original)
   outside=new/'Library/Application Support/generated.wav';outside.write_bytes(b'new')
   with self.assertRaises(AssertionError):run(new,True)
   outside.unlink()
   # Exact simctl-selected app and original owned simulator are both mandatory.
   wrong=base/str(uuid.uuid4());wrong.mkdir()
   with self.assertRaises(AssertionError):run(new,True,reported=wrong)
   with self.assertRaises(AssertionError):run(new,True,simulator=str(uuid.uuid4()))
   other=root/'Other/CoreSimulator/Devices'/sid/'data/Containers/Data/Application'/str(uuid.uuid4());other.parent.mkdir(parents=True);shutil.copytree(new,other)
   with self.assertRaises(AssertionError):run(other,True)
   target=new/'Library/Application Support/LocalVideoStudio/reference.wav';target.write_bytes(b'changed')
   with self.assertRaises(AssertionError):run(new,True)
   self.assertEqual(target.read_bytes(),b'changed');target.write_bytes(b'synthetic')
   extra=target.parent/'extra.wav';extra.write_bytes(b'new')
   with self.assertRaises(AssertionError):run(new,True)
   extra.unlink();target.unlink()
   with self.assertRaises(AssertionError):run(new,True)
