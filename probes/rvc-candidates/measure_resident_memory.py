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


from tools.rvc_hubert import HubertEncoder
from tools.rvc_chunking import plan,window
import resource,threading,shutil
outroot=ROOT/'rvc-resident-memory-20261115'
outroot.mkdir(exist_ok=False)
samples=[];stop=threading.Event();stage='load_encoder'
def rss(pid):
 try:
  for line in pathlib.Path('/proc',str(pid),'status').read_text().splitlines():
   if line.startswith('VmRSS:'):return int(line.split()[1])
 except (FileNotFoundError,ProcessLookupError):pass
 return 0
def descendants(pid):
 result=[]
 try:
  tasks=pathlib.Path('/proc',str(pid),'task')
  ids=set()
  for t in tasks.iterdir():
   try:ids.update(map(int,(t/'children').read_text().split()))
   except (FileNotFoundError,ProcessLookupError):pass
  for child in ids:result.append(child);result.extend(descendants(child))
 except (FileNotFoundError,ProcessLookupError):pass
 return result
def sample():
 while not stop.is_set():
  own=rss(os.getpid());children=sum(rss(p) for p in set(descendants(os.getpid())))
  samples.append(dict(stage=stage,parentKiB=own,childrenKiB=children,totalKiB=own+children))
  stop.wait(.02)
thread=threading.Thread(target=sample,daemon=True);thread.start()
encoder=HubertEncoder((ROOT/'voicematrix-hubert-assets').resolve())
reports=[]
for repeat in range(2):
 for name in ('5683-32865-0017','121-127105-0022'):
  stage=f'encode-{repeat}-{name}'
  previous=candidate/name;m=json.loads((previous/'manifest.json').read_text())
  payload=ROOT/'rvc-librispeech-broader-v2-20261115'/name/'payload'
  raw=_snapshot(payload/'prepared.f32',m['files']['prepared.f32'],10000000)
  audio=np.frombuffer(raw,dtype='<f4');chunk=list(plan(len(audio)))[0]
  padded=window(len(audio),chunk.input_start,lambda ids:audio[ids])
  features=encoder.extract(padded)[0]
  assert hashlib.sha256(features.astype('<f4').tobytes()).hexdigest()==m['featuresSHA256']
  folder=outroot/(str(repeat)+'-'+name);folder.mkdir()
  for filename in ('features.f32','pitch.json','latent.f32','phase.f32','excitation.f32'):
   shutil.copyfile(previous/filename,folder/filename)
  stage=f'native-{repeat}-{name}'
  subprocess.run(['/tmp/rvc-full-window-checks',str(folder),str(ROOT/'rvc-vctk-retrieval-pack-20261115'),str(ROOT/'rvc-disk-vector-20261115/cache')],check=True,timeout=120,capture_output=True)
  stage=f'synthesize-{repeat}-{name}'
  phone=np.fromfile(folder/'native/phone.f32',dtype='<f4').reshape(1,922,768)
  pitch=np.fromfile(folder/'native/pitch.i64',dtype='<i8').reshape(1,922)
  hz=np.fromfile(folder/'native/pitchf.f32',dtype='<f4').reshape(1,922)
  latent=np.fromfile(folder/'latent.f32',dtype='<f4').reshape(1,192,922)
  phase=np.fromfile(folder/'phase.f32',dtype='<f4').reshape(1,1)
  excitation=np.fromfile(folder/'excitation.f32',dtype='<f4').reshape(1,368800,1)
  args=tuple(torch.from_numpy(x) for x in (phone,np.array([922],dtype=np.int64),pitch,hz,np.array([0],dtype=np.int64),latent,phase,excitation))
  with torch.inference_mode():converted=adapter(*args).numpy().copy()
  count=(m['input16kSamples']*5+1)//2
  signal=converted[0,0,40000:40000+count]
  assert len(signal)==count and np.isfinite(signal).all() and np.abs(signal).max()<1
  destination=folder/'native.wav'
  with wave.open(str(destination),'wb') as w:
   w.setparams((1,2,40000,0,'NONE','not compressed'));w.writeframes(np.rint(signal*32767).astype('<i2').tobytes())
  digest=hashlib.sha256(destination.read_bytes()).hexdigest()
  expected=json.loads((previous/'comparison.json').read_text())['outputSHA256']['native']
  assert digest==expected,(digest,expected)
  reports.append(dict(case=name,repeat=repeat,outputSHA256=digest,exactPriorWAV=True))
  print(json.dumps(reports[-1]),flush=True)
  del converted,args,phone,pitch,hz,latent,phase,excitation,features;gc.collect()
stage='close';encoder.close();del net,adapter,checkpoint;gc.collect()
time.sleep(.1);stop.set();thread.join()
stages={}
for row in samples:
 s=stages.setdefault(row['stage'],dict(parentPeakKiB=0,childrenPeakKiB=0,combinedPeakKiB=0))
 for key,field in [('parentPeakKiB','parentKiB'),('childrenPeakKiB','childrenKiB'),('combinedPeakKiB','totalKiB')]:s[key]=max(s[key],row[field])
report=dict(cases=reports,stages=stages,combinedSampledPeakKiB=max(x['totalKiB'] for x in samples),parentLifetimePeakKiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,sampleIntervalSeconds=.02,samples=len(samples),scope='Linux PyTorch evaluation with encoder and synthesizer simultaneously resident; native retrieval child RSS added. Not ONNX Runtime or iPhone memory.',limitations=['20ms sampled sums may miss short peaks and double-count shared pages.','PyTorch, Python imports and retained checkpoint affect memory; no whole-app memory equivalence.','Two repeated regression cases are not new held-out quality evidence.'],allPassed=True)
(outroot/'result.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report),flush=True)

# Child RSS coverage was zero in this run. Use the corrected parent-only
# report in docs/qa/resident-model-memory/result.json, not a combined-RSS claim.
