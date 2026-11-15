import pathlib,sys,os,json,hashlib,io,wave,time,types,importlib.abc,importlib.util,linecache,socket,subprocess,gc
ROOT=pathlib.Path.cwd()
sys.path[:0]=[str(ROOT/'voicematrix-hubert-deps'),str(ROOT/'voicematrix-unicode-candidate')]
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',OMP_NUM_THREADS='2',CUDA_VISIBLE_DEVICES='')
def offline(*a,**kw):raise RuntimeError('Network disabled during inference')
socket.socket.connect=offline;socket.create_connection=offline
import numpy as np,torch,faiss
from tools.rvc_onnx_runtime import _snapshot
from tools.rvc_portable import _adapter,_capture_random
from tools.rvc_validation import _speaker_config
SOURCE=ROOT/'voicematrix-unicode-candidate/probes/rvc-long/source'
SOURCE_HASHES={"models.py":"769615b8dbed4775c8083881663a79c0e5ec0b662dd5f0c0a1bc3ccdd9827e99","modules.py":"b1aa77b0921468a61492fa89ed1f1212cd22fee3caa551befe44d8ab359fd2f1","attentions.py":"8820e6047353d99344fc73fbb6c69d85e4f61066fc498982cc895e9577d4519f","commons.py":"132a907eff444907861e63684c04c88ae631d03707470858f7c53f857b0cc5c8","transforms.py":"fb0d3320adf32ca0eaa44dd56e8922927f77ec3dd45c775e10c3da1704072c6a"}
MODEL_HASH='3c4c2e8ea977d7c08793126aace4baa47028b4c1bf7cd46ae5a9c359b0216693'
candidate=ROOT/'rvc-native-full-window-20261115'
"""Hash-bound FAISS CPU retrieval for RVC's eight-neighbor feature stage.

Only load trusted index hashes. FAISS deserialization is not a sandbox.
No index mutation, training, downloads or publication.
"""
import threading
from tools.rvc_onnx_runtime import _snapshot, _cancel

class EvaluationIndex:
    def __init__(self,path,expected_sha256):
        import numpy as np
        import faiss
        if np.__version__ != '1.26.4' or faiss.__version__ != '1.13.2':
            raise ValueError('Use NumPy 1.26.4 and FAISS CPU 1.13.2')
        assert expected_sha256=='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
        raw=_snapshot(path,expected_sha256,160*1024*1024)
        index=faiss.deserialize_index(np.frombuffer(raw,dtype=np.uint8).copy())
        if (index.d != 768 or not index.is_trained or index.ntotal != 45313 or
                index.metric_type != faiss.METRIC_L2):
            raise ValueError('Expected populated bounded 768-dimensional L2 index')
        vectors=index.reconstruct_n(0,index.ntotal)
        if vectors.shape != (index.ntotal,768) or vectors.dtype != np.float32 or not np.isfinite(vectors).all():
            raise ValueError('Invalid reconstructed index vectors')
        self._index,self._vectors,self._np=index,vectors,np
        self._lock=threading.Lock()
        self.index_sha256=expected_sha256
        self.vector_count=int(index.ntotal)

    def search(self,features,*,cancel=None):
        _cancel(cancel);np=self._np
        if (not isinstance(features,np.ndarray) or features.ndim != 2 or
                features.shape[1] != 768 or not 1 <= len(features) <= 1500 or
                features.dtype != np.float32):
            raise ValueError('Expected bounded float32 feature rows')
        query=np.array(features,dtype=np.float32,order='C',copy=True)
        if not np.isfinite(query).all():raise ValueError('Nonfinite query')
        with self._lock:
            _cancel(cancel)
            distances,ids=self._index.search(query,8)
        _cancel(cancel)
        # Preserve nprobe=1 unless a row lacks neighbors. Search the existing
        # bounded vector bank in 256-vector blocks; never pad with fabricated IDs.
        for row in np.flatnonzero((ids<0).any(axis=1)):
            exact=np.empty(self.vector_count,dtype=np.float64)
            for start in range(0,self.vector_count,256):
                _cancel(cancel)
                block=self._vectors[start:start+256].astype(np.float64)
                block-=query[row].astype(np.float64)
                exact[start:start+len(block)]=np.einsum('ij,ij->i',block,block)
            selected=np.lexsort((np.arange(self.vector_count),exact))[:8]
            ids[row]=selected;distances[row]=exact[selected].astype(np.float32)
        _cancel(cancel)
        if (not np.isfinite(distances).all() or (distances<=0).any() or
                (ids<0).any() or (ids>=self.vector_count).any()):
            raise ValueError('Missing or degenerate retrieval neighbors')
        return dict(distances=distances.copy(),ids=ids.copy(),vectors=self._vectors[ids].copy())

source={'infer':b'','infer.module':b''}
for name,digest in SOURCE_HASHES.items():
 source['infer.module.'+name[:-3]]=_snapshot(SOURCE/'infer'/'module'/name,digest,1024*1024)
class Loader(importlib.abc.MetaPathFinder,importlib.abc.Loader):
 def find_spec(self,name,path=None,target=None):
  if name in source:return importlib.util.spec_from_loader(name,self,is_package=name in ('infer','infer.module'))
  if name.startswith('infer.'):raise ImportError('Outside verified inference source closure')
 def create_module(self,spec):return None
 def exec_module(self,module):
  raw=source[module.__name__];filename=str(SOURCE/(module.__name__.replace('.','/')+'.py'))
  module.__file__=filename;linecache.cache[filename]=(len(raw),None,raw.decode().splitlines(True),filename)
  exec(compile(raw,filename,'exec'),module.__dict__)
if any(n=='infer' or n.startswith('infer.') for n in sys.modules):raise ValueError('Inference namespace already imported')
sys.meta_path.insert(0,Loader())
from infer.module.models import SynthesizerTrnMs768NSFsid
torch.set_num_threads(2);torch.set_num_interop_threads(1);faiss.omp_set_num_threads(2)
checkpoint=torch.load(io.BytesIO(_snapshot(candidate/'Mp226.pth',MODEL_HASH,128*1024*1024)),map_location='cpu',weights_only=True)
if checkpoint.get('version')!='v2' or checkpoint.get('f0')!=1:raise ValueError('Expected pitch-aware v2 model')
config=_speaker_config(checkpoint['config'],checkpoint['weight']['emb_g.weight'])
net=SynthesizerTrnMs768NSFsid(*config,is_half=False);del net.enc_q
missing,unexpected=net.load_state_dict(checkpoint['weight'],strict=False)
if missing or any(not x.startswith('enc_q.') for x in unexpected):raise ValueError('Model state mismatch')
net.eval().float();adapter=_adapter(torch,net)


index=EvaluationIndex(ROOT/'vctk-p226-verified.index','7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50')
reports=[]
def metrics(a,b):
 assert a.shape==b.shape and np.isfinite(a).all() and np.isfinite(b).all()
 d=a.astype(np.float64)-b
 return dict(maxAbs=float(np.max(np.abs(d))),rms=float(np.sqrt(np.mean(d*d))))
for name in ('5683-32865-0017','121-127105-0022'):
 out=candidate/name;m=json.loads((out/'manifest.json').read_text())
 features=np.frombuffer(_snapshot(out/'features.f32',m['featuresSHA256'],2000000),dtype='<f4').reshape(461,768).copy()
 found=index.search(features);weights=(1/found['distances'])**2;weights/=weights.sum(axis=1,keepdims=True)
 mixed=(found['vectors']*weights[:,:,None]).sum(axis=1)*.125+features*.875
 pitch=np.array(json.loads((out/'pitch.json').read_text())[0],dtype=np.float64)
 voiced=pitch>0
 if voiced.any():pitch[~voiced]=np.interp(np.flatnonzero(~voiced),np.flatnonzero(voiced),pitch[voiced])
 mel=1127*np.log1p(pitch/700);lo=1127*np.log1p(50/700);hi=1127*np.log1p(1100/700)
 coarse=np.rint(np.clip(np.where(mel>0,(mel-lo)*254/(hi-lo)+1,mel),1,255)).astype(np.int64)[:922]
 pitchf=pitch[:922].astype(np.float32);mask=np.where(pitchf<1,.33,1).astype(np.float32)[:,None]
 phone=np.repeat(mixed,2,axis=0)*mask+np.repeat(features,2,axis=0)*(1-mask)
 args=(torch.from_numpy(phone[None,:]),torch.tensor([922]),torch.from_numpy(coarse[None,:]),torch.from_numpy(pitchf[None,:]),torch.tensor([0]))
 torch.manual_seed(347)
 with torch.inference_mode(),_capture_random(torch) as draws:reference=net.infer(*args)[0].numpy().copy()
 assert len(draws)==3 and [k for k,v in draws]==['normal','uniform','normal']
 for filename,(kind,value) in zip(('latent.f32','phase.f32','excitation.f32'),draws):(out/filename).write_bytes(value.numpy().astype('<f4').tobytes())
 wrapper="import subprocess,resource,json,sys;p=subprocess.run(sys.argv[1:],capture_output=True,text=True);print(json.dumps(dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr[-2000:],maxRSSKiB=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)));sys.exit(p.returncode)"
 run=subprocess.run([sys.executable,'-c',wrapper,'/tmp/rvc-full-window-checks',str(out),str(ROOT/'rvc-vctk-retrieval-pack-20261115'),str(ROOT/'rvc-disk-vector-20261115/cache')],capture_output=True,text=True,timeout=120)
 assert run.returncode==0,(run.stdout,run.stderr)
 process=json.loads(run.stdout);nativeReport=json.loads((out/'native/result.json').read_text())
 nativePhone=np.fromfile(out/'native/phone.f32',dtype='<f4').reshape(922,768)
 nativePitch=np.fromfile(out/'native/pitch.i64',dtype='<i8');nativeHz=np.fromfile(out/'native/pitchf.f32',dtype='<f4')
 inputError=metrics(nativePhone,phone);hzError=metrics(nativeHz,pitchf)
 ids=np.array(nativeReport['neighborIDs']).reshape(461,8);idDifferences=int((ids!=found['ids']).sum())
 nativeArgs=(torch.from_numpy(nativePhone[None,:]),torch.tensor([922]),torch.from_numpy(nativePitch[None,:]),torch.from_numpy(nativeHz[None,:]),torch.tensor([0]))+tuple(value for kind,value in draws)
 with torch.inference_mode():
  baseline=adapter(*(args+tuple(value for kind,value in draws))).numpy().copy()
  converted=adapter(*nativeArgs).numpy().copy()
 adapterError=metrics(reference,baseline);audioError=metrics(baseline,converted)
 samples=(m['input16kSamples']*5+1)//2
 for label,a in [('reference',baseline),('native',converted)]:
  signal=a[0,0,40000:40000+samples]
  assert len(signal)==samples and np.isfinite(signal).all() and np.abs(signal).max()<1
  with wave.open(str(out/(label+'.wav')),'wb') as w:
   w.setparams((1,2,40000,0,'NONE','not compressed'));w.writeframes(np.rint(signal*32767).astype('<i2').tobytes())
 report=dict(case=name,rows=461,neighbors=3688,neighborIDDifferences=idDifferences,coarsePitchExact=bool(np.array_equal(nativePitch,coarse)),pitchHzError=hzError,phoneError=inputError,originalAdapterError=adapterError,nativeReferenceAudioError=audioError,nativeProcess=process,nativeLoadSeconds=nativeReport['loadSeconds'],nativePrepareSeconds=nativeReport['prepareSeconds'],outputSamples=samples,outputSHA256={label:hashlib.sha256((out/(label+'.wav')).read_bytes()).hexdigest() for label in ('reference','native')},inputProvenance=m,physicalIPhoneVerified=False,humanListeningVerified=False)
 report['parityPassed']=bool(idDifferences==0 and np.array_equal(nativePitch,coarse) and np.allclose(nativePhone,phone,rtol=3e-5,atol=2e-6) and adapterError['maxAbs']<=1e-6 and adapterError['rms']<=1e-7 and audioError['maxAbs']<=2e-4 and audioError['rms']<=2e-5)
 (out/'comparison.json').write_text(json.dumps(report,indent=2));reports.append(report)
 print(json.dumps({k:report[k] for k in ('case','neighborIDDifferences','coarsePitchExact','phoneError','nativeReferenceAudioError','parityPassed','nativeLoadSeconds','nativePrepareSeconds')}),flush=True)
 del reference,baseline,converted;gc.collect()
(candidate/'comparison.json').write_text(json.dumps(dict(cases=reports,modelSHA256=MODEL_HASH,sourceHashes=SOURCE_HASHES,sourceRevision='81eed5e8f68b6bed1789f682fe78cdd324495afc',scope='Native pack loader/retrieval/preparation feeding a controlled CPU PyTorch synthesizer; not iPhone execution',allPassed=all(r['parityPassed'] for r in reports)),indent=2))
