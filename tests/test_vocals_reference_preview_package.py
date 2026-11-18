"""Preserve old packaging gates; inspect exact separation bytes before upload."""
import copy,hashlib,importlib.util,json,pathlib,stat,tempfile,unittest,zipfile
import yaml
from tools.test_shell import check_bash_syntax
ROOT=pathlib.Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('resource_inspection',ROOT/'tools/verification/inspect_handoff_separation_resources.py')
inspection=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(inspection)
TARGET='cd235ec71960a3586a267dcdfd8a94d8a4e69d0f'
IPA='VoiceMatrix-0.4.14-build17-vocals-reference-preview-cd235ec.ipa'
PREFIX='''set -e
actual_source=$(git rev-parse HEAD)
test "$actual_source" = "$TARGET_SOURCE"
# Build evidence must name the immutable app source, not this workflow commit.
export GITHUB_SHA="$actual_source"
'''

class PackagingPolicyTests(unittest.TestCase):
 def setUp(self):
  self.base=yaml.safe_load((ROOT/'.github/workflows/iphone-build17.yml').read_text())
  self.preview=yaml.safe_load((ROOT/'.github/workflows/iphone-vocals-reference-preview.yml').read_text())
 def test_trigger_source_and_harness_identity(self):
  self.assertEqual(self.preview['on'],{'push':{'branches':['packaging/separated-vocals-reference-preview']},'workflow_dispatch':None})
  self.assertEqual(self.preview['permissions'],{'contents':'read','actions':'read'})
  self.assertEqual(self.preview['env'],{'TARGET_SOURCE':TARGET,'PACKAGING_WORKFLOW_COMMIT':'${{ github.sha }}'})
  self.assertEqual(inspection.TARGET_SOURCE,TARGET)
 def test_all_prior_three_job_gates_remain_unchanged(self):
  jobs=copy.deepcopy(self.preview['jobs'])
  additions={'Stage exact licensed vocal separation models before project generation','Independently inspect exact separation models and licenses inside original IPA','Verify isolated packaging harness policy and ZIP regressions'}
  for job in jobs.values():
   normalized=[]
   for step in job['steps']:
    if step.get('uses')=='actions/checkout@v4' and step.get('with',{}).get('path')=='packaging-harness':
     self.assertEqual(step['with'],{'ref':'${{ github.sha }}','path':'packaging-harness','persist-credentials':False});continue
    if step.get('name') in additions:continue
    if step.get('uses')=='actions/checkout@v4':self.assertEqual(step.pop('with'),{'ref':TARGET})
    if 'run' in step:
     self.assertTrue(step['run'].startswith(PREFIX))
     run=step['run'][len(PREFIX):].replace(IPA,'VoiceMatrix-0.4.14-build17.ipa')
     run=run.replace("sourceCommit=os.environ['GITHUB_SHA'],packagingWorkflowCommit=os.environ['PACKAGING_WORKFLOW_COMMIT'],previewLabel='vocals-reference-artifact-only',","sourceCommit=os.environ['GITHUB_SHA'],")
     run=run.replace("purpose='Unsigned vocals reference handoff preview; packaging and asset inspection only'","purpose='Unsigned iPhone preview; packaging and asset inspection only'")
     run=run.replace("musicSeparation='experimental-up-to-10-second-two-stem-diagnostic'",'musicSeparation=False')
     step['run']=run
    if step.get('uses') in ('actions/upload-artifact@v4','actions/download-artifact@v4'):
     self.assertTrue(step['with']['name'].startswith('Vocals-reference-preview-'))
     step['with']['name']=step['with']['name'].removeprefix('Vocals-reference-preview-')
     if 'path' in step['with']:step['with']['path']=step['with']['path'].replace(IPA,'VoiceMatrix-0.4.14-build17.ipa').replace('\n\nseparation-inspection.json','')
    normalized.append(step)
   job['steps']=normalized
  self.assertEqual(jobs,self.base['jobs'])
 def test_stages_before_build_and_inspects_before_upload(self):
  steps=self.preview['jobs']['ipa']['steps'];names=[s.get('name','') for s in steps]
  stage=names.index('Stage exact licensed vocal separation models before project generation')
  inspect=names.index('Independently inspect exact separation models and licenses inside original IPA')
  self.assertLess(stage,names.index('Resolve frozen graph'))
  self.assertGreater(inspect,names.index('Collect dependency licenses and compile unsigned ARM64 app'))
  upload=next(i for i,s in enumerate(steps) if s.get('uses')=='actions/upload-artifact@v4')
  self.assertLess(inspect,upload)
  self.assertIn('separation-inspection.json',steps[upload]['with']['path'])
  for job in self.preview['jobs'].values():
   for step in job['steps']:
    if 'run' in step:check_bash_syntax(step['run']);self.assertNotIn('gh release',step['run'])

 def test_two_licensed_readers_and_handoff_source_graph_remain_bound(self):
  pipeline='\n'.join(s.get('run','') for s in self.preview['jobs']['native-pipeline']['steps'])
  for required in ['probes/full-retained-speaker-route/prepare.py local-evidence/first',
                   'probes/second-complete-speaker-route/prepare.py local-evidence/second',
                   'for reader in first second;', 'sandbox-exec', 'deny network*']:
   self.assertIn(required,pipeline)
  proof=(ROOT/'tools/character_evidence.py').read_text()
  self.assertIn("pathlib.Path('VoiceMatrix').glob('*.swift')",proof)
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  paths=[s['path'] for s in project['targets']['LocalStudioDiagnostic']['sources'] if isinstance(s,dict)]
  for name in ['LocalVideoStudio','SeparationStore','VocalSeparationAssets','RetainedMediaReader']:
   self.assertIn('VoiceMatrix/'+name+'.swift',paths)
  for name in ['LocalVideoStudioView','VocalSeparationView']:
   self.assertTrue((ROOT/'VoiceMatrix'/ (name+'.swift')).is_file())

class ResourceInspectionTests(unittest.TestCase):
 def setUp(self):
  self.model={'vocals.onnx':b'known-vocals','accompaniment.onnx':b'known-backing'}
  self.pins={n:(len(data),hashlib.sha256(data).hexdigest()) for n,data in self.model.items()}
  self.provenance={'testOnly':True};self.notices={'LICENSES.txt':'full license fixture','NOTICE.txt':'attribution fixture'}
 def write(self,path,changes=None,extra=None):
  files={**self.model,**{n:t.encode() for n,t in self.notices.items()},'manifest.json':json.dumps(self.provenance).encode()}
  files.update(changes or {})
  with zipfile.ZipFile(path,'w') as z:
   for name,data in files.items():
    if data is not None:z.writestr('Payload/VoiceMatrix.app/Separation/'+name,data)
   if extra:z.writestr(*extra)
 def inspect(self,path):return inspection.inspect_resources(path,self.pins,self.provenance,self.notices)
 def test_exact_models_and_notices_accepted(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td)/'test.ipa';self.write(p);result=self.inspect(p)
   self.assertTrue(result['passed']);self.assertFalse(result['physicalDeviceVerified']);self.assertEqual(len(result['resources']),5)
 def test_mutated_missing_unlicensed_and_extra_resources_rejected(self):
  for change in [{'vocals.onnx':b'changed-data'},{'vocals.onnx':None},{'NOTICE.txt':None},{'LICENSES.txt':b'wrong'},{'manifest.json':b'{}'},{'extra.onnx':b'x'}]:
   with self.subTest(change=list(change)),tempfile.TemporaryDirectory() as td:
    p=pathlib.Path(td)/'test.ipa';self.write(p,change)
    with self.assertRaises(ValueError):self.inspect(p)
 def test_link_duplicate_and_normalized_resource_rejected(self):
  prefix='Payload/VoiceMatrix.app/Separation/'
  link=zipfile.ZipInfo(prefix+'link');link.external_attr=(stat.S_IFLNK|0o777)<<16
  raw=zipfile.ZipInfo('placeholder');raw.filename=prefix+'bad\x00hidden';raw.orig_filename=raw.filename
  for extra in [(link,b'vocals.onnx'),(prefix+'vocals.onnx',b'duplicate'),(raw,b'x')]:
   with self.subTest(extra=str(extra[0])),tempfile.TemporaryDirectory() as td:
    p=pathlib.Path(td)/'test.ipa';self.write(p,extra=extra)
    with self.assertRaises(ValueError):self.inspect(p)
