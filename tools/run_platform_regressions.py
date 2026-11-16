"""Keep Windows worker coverage separate from POSIX Swift harnesses.

No native check is waived: the full Linux lane must execute every delegated ID
successfully (not skip it). Both matrix jobs remain required workflow gates.
"""
import argparse,json,os,pathlib,re,sys,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
MANIFEST=ROOT/'tests/platform-regression-coverage.json'

def flatten(suite):
 for item in suite:
  if isinstance(item,unittest.TestSuite):yield from flatten(item)
  else:yield item

def select(suite,mode,delegated):
 tests=list(flatten(suite));ids=[t.id() for t in tests]
 if len(ids)!=len(set(ids)):raise ValueError('Duplicate test identity')
 if not delegated or not set(delegated)<=set(ids):raise ValueError('Missing delegated test identity')
 if mode not in ('full','windows-worker'):raise ValueError('Unknown platform suite')
 return unittest.TestSuite(t for t in tests if mode=='full' or t.id() not in delegated)

def native_coverage_passed(result,delegated):
 return set(delegated)<=result.passed and result.wasSuccessful()

class EvidenceResult(unittest.TextTestResult):
 def __init__(self,*args,**kwargs):super().__init__(*args,**kwargs);self.passed=set()
 def addSuccess(self,test):super().addSuccess(test);self.passed.add(test.id())

def main():
 p=argparse.ArgumentParser();p.add_argument('--mode',choices=['full','windows-worker'],required=True);a=p.parse_args()
 if (a.mode=='windows-worker') != (sys.platform=='win32'):raise RuntimeError('Platform/mode mismatch')
 if os.environ.get('GITHUB_ACTIONS')=='true' and not re.fullmatch('[0-9a-f]{40}',os.environ.get('GITHUB_SHA','')):raise RuntimeError('Missing CI source identity')
 manifest=json.loads(MANIFEST.read_text(encoding='utf-8'));delegated=manifest['posixSwiftTestIDs']
 if len(delegated)!=len(set(delegated)):raise ValueError('Duplicate delegated identity')
 suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'))
 selected=select(suite,a.mode,delegated)
 result=unittest.TextTestRunner(verbosity=2,resultclass=EvidenceResult).run(selected)
 covered=native_coverage_passed(result,delegated) if a.mode=='full' else None
 evidence=dict(sourceCommit=os.environ.get('GITHUB_SHA'),mode=a.mode,testsRun=result.testsRun,passed=sorted(result.passed),skipped=[dict(id=t.id(),reason=r) for t,r in result.skipped],delegatedToLinux=delegated if a.mode=='windows-worker' else [],allDelegatedExecutedSuccessfully=covered,successful=result.wasSuccessful())
 pathlib.Path('platform-regression-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
 if not result.wasSuccessful() or (a.mode=='full' and not covered):raise SystemExit(1)
if __name__=='__main__':main()
