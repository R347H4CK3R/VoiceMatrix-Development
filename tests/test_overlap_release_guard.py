import unittest,importlib.util,pathlib,copy
ROOT=pathlib.Path(__file__).resolve().parents[1]
class GuardTests(unittest.TestCase):
 def test_native_target_contains_overlap_dependency(self):
  import yaml
  p=yaml.safe_load((ROOT/'project.yml').read_text())
  self.assertIn({'path':'VoiceMatrix/LocalOverlapPolicy.swift'},p['targets']['LocalStudioDiagnostic']['sources'])
 def test_workflows_have_valid_branch_filters(self):
  import yaml
  for p in (ROOT/'.github/workflows').glob('*.yml'):
   d=yaml.safe_load(p.read_text());on=d.get('on',d.get(True,{}))
   if isinstance(on,dict):
    push=on.get('push',{})
    if isinstance(push,dict):self.assertFalse('branches' in push and 'branches-ignore' in push,p.name)
 def test_results_fail_closed(self):
  spec=importlib.util.spec_from_file_location('guard',ROOT/'probes/overlap-stress/verify_guard.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  rows=[dict(id=k,candidates=6,retained=6,excluded=0) for k in ['single-A','sequential','partial-2s']]+[dict(id=k,candidates=6,retained=1,excluded=5) for k in ['full-equal','full-quieter']]
  m.validate_results(rows)
  for mutate in [lambda a:a.pop(),lambda a:a.append(a[0]),lambda a:a[0].update(retained=0,excluded=6),lambda a:a[-1].update(retained=6,excluded=0),lambda a:a[-1].update(excluded=4)]:
   bad=copy.deepcopy(rows);mutate(bad)
   with self.assertRaises((AssertionError,ValueError)):m.validate_results(bad)
