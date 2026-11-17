import importlib.util,pathlib,unittest
p=pathlib.Path(__file__).resolve().parents[1]/'tools/select_ios26_simulator.py'
s=importlib.util.spec_from_file_location('selector',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Simulator(unittest.TestCase):
 def test_only_available_ios26_iphone(self):
  d={'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-18-0':[{'name':'iPhone16','udid':'old','isAvailable':True}], 'com.apple.CoreSimulator.SimRuntime.iOS-26-0':[{'name':'iPhone17','udid':'unavailable','isAvailable':False},{'name':'iPad','udid':'ipad','isAvailable':True},{'name':'iPhone17','udid':'wanted','isAvailable':True}]}}
  self.assertEqual(m.select(d),'wanted')
 def test_missing_required_runtime_fails(self):
  with self.assertRaises(ValueError):m.select({'devices':{}})
