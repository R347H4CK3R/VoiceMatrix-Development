import copy, importlib.util, io, pathlib, stat, tempfile, unittest, zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('inspection', ROOT/'tools/verification/inspect_build17_artifact.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class IndependentInspectionTests(unittest.TestCase):
    def metadata(self):
        return {'id':m.ARTIFACT,'name':'Character-test-IPA','size_in_bytes':m.ZIP_SIZE,'expired':False,'digest':'sha256:'+m.ZIP_SHA,'workflow_run':{'id':m.RUN,'head_sha':m.COMMIT}}, {'status':'completed','conclusion':'success','path':'.github/workflows/iphone-build17.yml','id':m.RUN,'head_sha':m.COMMIT,'repository':{'full_name':m.REPO}}
    def test_exact_metadata_accepted(self): m.validate_metadata(*self.metadata())
    def test_changed_provenance_and_expired_artifact_rejected(self):
        for field,value in [('id',1),('name','other'),('size_in_bytes',1),('expired',True),('digest','sha256:'+'0'*64),('workflow_run',{'id':1,'head_sha':m.COMMIT}),('workflow_run',{'id':m.RUN,'head_sha':'0'*40})]:
            a,r=self.metadata();a[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):m.validate_metadata(a,r)
        for field,value in [('status','in_progress'),('conclusion','failure'),('path','other.yml'),('id',1),('head_sha','0'*40),('repository',{'full_name':'other/repo'})]:
            a,r=self.metadata();r[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):m.validate_metadata(a,r)
    def archive(self,names):
        b=io.BytesIO()
        with zipfile.ZipFile(b,'w') as z:
            for name,mode in names:
                i=zipfile.ZipInfo(name);i.external_attr=mode<<16;z.writestr(i,b'x')
        b.seek(0);return zipfile.ZipFile(b)
    def test_unsafe_names_and_special_files_rejected(self):
        for name,mode in [('../escape',stat.S_IFREG),('/absolute',stat.S_IFREG),('a/../escape',stat.S_IFREG),('a\\b',stat.S_IFREG),('a//b',stat.S_IFREG),('a/./b',stat.S_IFREG),('C:drive',stat.S_IFREG),('link',stat.S_IFLNK),('device',stat.S_IFCHR)]:
            with self.subTest(name=name),self.archive([(name,mode)]) as z,self.assertRaises(ValueError):m.checked_members(z,1024)
    def test_duplicates_case_collisions_and_size_rejected(self):
        with self.archive([('a',stat.S_IFREG),('A',stat.S_IFREG)]) as z,self.assertRaises(ValueError):m.checked_members(z,1024)
        with self.archive([('a',stat.S_IFREG)]) as z,self.assertRaises(ValueError):m.checked_members(z,0)
    def test_regular_file_safely_extracted(self):
        with tempfile.TemporaryDirectory() as t,self.archive([('dir/file',stat.S_IFREG)]) as z:
            out=pathlib.Path(t)/'extract';m.extract(z,out,m.checked_members(z,1024));self.assertEqual((out/'dir/file').read_bytes(),b'x')
    def test_workflow_cannot_publish_or_rebuild(self):
        text=(ROOT/'.github/workflows/independent-build17-inspection.yml').read_text()
        self.assertIn('branches: [verification/standalone-mkv-ipa-inspection]',text)
        self.assertIn('ref: '+m.COMMIT,text)
        self.assertIn('contents: read',text);self.assertIn('actions: read',text)
        self.assertNotIn('xcodebuild',text);self.assertNotIn('gh release',text)
        self.assertLess(text.index('metadata evidence/'),text.index('/14406432049/zip'))
        self.assertIn('path: evidence',text)
    def test_source_and_lock_proof_and_all_inspectors_required(self):
        source=(ROOT/'tools/verification/inspect_build17_artifact.py').read_text()
        for marker in ['digest(archive) != ZIP_SHA','digest(ipa) != match[1]','embedded_lock.read_bytes() != lock.read_bytes()',"source != json.loads(expected.read_text())",'tools.character_evidence','tools.frozen_vendored_graph','tools/character_package.py','tools/bundle_diarization.py','tools/bundle_asr.py','tools/python-runtime/prepare_app_python.py','tools/python-runtime/verify_python_bundle.py']:
            self.assertIn(marker,source)
