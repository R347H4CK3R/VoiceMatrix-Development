import importlib.util,io,pathlib,unittest,urllib.error
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
def module():
 p=ROOT/'probes/reference-context-human-holdouts/prepare.py';s=importlib.util.spec_from_file_location('retry_prepare',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class RetryTests(unittest.TestCase):
 def test_retry_is_implemented(self):self.assertTrue(hasattr(module(),'fetch'),'Transient acquisition retry missing')
 def test_transient_failure_then_success_preserves_attempts_and_url(self):
  m=module();records=[];url='https://example.invalid/row'
  with patch.object(m.urllib.request,'urlopen',side_effect=[urllib.error.HTTPError(url,500,'InternalServerError',{},None),io.BytesIO(b'complete')]) as open_,patch.object(m.time,'sleep') as sleep:
   self.assertEqual(m.fetch(url,20,'row',records),b'complete');self.assertEqual(open_.call_count,2);self.assertEqual([c.args[0] for c in open_.call_args_list],[url,url]);sleep.assert_called_once_with(1)
  self.assertEqual([r['ok'] for r in records],[False,True]);self.assertEqual(records[0]['status'],500)
 def test_terminal_and_bounded_failures(self):
  m=module();url='https://example.invalid/row'
  for code,calls in [(403,1),(404,1),(500,3),(429,3)]:
   with self.subTest(code=code),patch.object(m.urllib.request,'urlopen',side_effect=urllib.error.HTTPError(url,code,'failure',{},None)) as open_,patch.object(m.time,'sleep'):
    records=[]
    with self.assertRaises(urllib.error.HTTPError):m.fetch(url,20,'source',records)
    self.assertEqual(open_.call_count,calls);self.assertEqual(len(records),calls)
 def test_timeouts_retry_but_oversize_does_not(self):
  m=module();records=[]
  with patch.object(m.urllib.request,'urlopen',side_effect=[TimeoutError('timeout'),io.BytesIO(b'ok')]),patch.object(m.time,'sleep'):
   self.assertEqual(m.fetch('https://example.invalid',4,'row',records),b'ok');self.assertEqual(len(records),2)
  with patch.object(m.urllib.request,'urlopen',return_value=io.BytesIO(b'12345')) as open_,patch.object(m.time,'sleep'):
   with self.assertRaises(ValueError):m.fetch('https://example.invalid',4,'row',[])
   self.assertEqual(open_.call_count,1)
if __name__=='__main__':unittest.main()
