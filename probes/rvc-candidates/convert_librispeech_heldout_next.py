"""Private full-speech RVC retrieval and longer fixed-profile synthesis check.

Run only against the approved rvc-smoke-20261112 fixture workspace.
Writes new outputs under its isolated codex-runtime-20261114 directory.
No publication, source-audio truncation or model/index mutation.
"""
import pathlib,sys,os,json,hashlib,io,wave,time,math,types,importlib.abc,importlib.util,linecache,socket
ROOT=pathlib.Path(__file__).resolve().parent
sys.path[:0]=[str(ROOT/'deps-long'),str(ROOT/'source-long')]
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',CUDA_VISIBLE_DEVICES='',OMP_NUM_THREADS='2')
def offline(*args,**kwargs):raise RuntimeError('Network disabled during fixture execution')
socket.socket.connect=offline;socket.create_connection=offline
import numpy as np,torch,faiss
from scipy.signal import resample_poly,butter,filtfilt
from tools.rvc_onnx_runtime import _snapshot,RVCSynthesizer
from tools.rvc_hubert import HubertEncoder
from tools.rvc_pitch import extract_pm
from tools.rvc_retrieval import RVCIndex
from tools.rvc_portable import _adapter,_capture_random
from tools.rvc_validation import _speaker_config

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
        assert expected_sha256 == '7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
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

SOURCE_HASHES={"models.py":"769615b8dbed4775c8083881663a79c0e5ec0b662dd5f0c0a1bc3ccdd9827e99","modules.py":"b1aa77b0921468a61492fa89ed1f1212cd22fee3caa551befe44d8ab359fd2f1","attentions.py":"8820e6047353d99344fc73fbb6c69d85e4f61066fc498982cc895e9577d4519f","commons.py":"132a907eff444907861e63684c04c88ae631d03707470858f7c53f857b0cc5c8","transforms.py":"fb0d3320adf32ca0eaa44dd56e8922927f77ec3dd45c775e10c3da1704072c6a"}
MODEL_HASH='3c4c2e8ea977d7c08793126aace4baa47028b4c1bf7cd46ae5a9c359b0216693'
INDEX_HASH='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
INPUT_HASH='9103f5cdff17596db5607af444fea5abbd9c96e59ae79509c1dbdc0390d4920c'
started=time.monotonic();base=ROOT.parent
case_name=sys.argv[1]
assert case_name in ('2961-960-0003','4507-16021-0031')
rate=float(sys.argv[2]);assert rate in (0,.125)
rate_tag={0:'0',.125:'0125'}[rate]
candidate=ROOT/'candidate-vctk-p226'
out=candidate/('librispeech-'+case_name+'-'+rate_tag);out.mkdir(exist_ok=False)
def progress(stage,**extra):print(json.dumps(dict(stage=stage,**extra)),flush=True)
source={'infer':b'','infer.module':b''}
for name,digest in SOURCE_HASHES.items():
 source['infer.module.'+name[:-3]]=_snapshot(ROOT/'source-long'/'infer'/'module'/name,digest,1024*1024)
class Loader(importlib.abc.MetaPathFinder,importlib.abc.Loader):
 def find_spec(self,name,path=None,target=None):
  if name in source:return importlib.util.spec_from_loader(name,self,is_package=name in ('infer','infer.module'))
  if name.startswith('infer.'):raise ImportError('Outside verified inference source closure')
 def create_module(self,spec):return None
 def exec_module(self,module):
  raw=source[module.__name__];filename=str(ROOT/'source-long'/(module.__name__.replace('.','/')+'.py'))
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

from tools.rvc_chunking import convert,plan
payload=ROOT/'librispeech-heldout-next-inputs'/case_name
manifest=json.loads((payload/'manifest.json').read_text())
audio=np.frombuffer(_snapshot(payload/'prepared.f32',manifest['files']['prepared.f32'],480000*4),dtype='<f4').copy()
native_pitch=json.loads(_snapshot(payload/'pitch.json',manifest['files']['pitch.json'],128*1024))

with wave.open(str(out/'prepared-input.wav'),'wb') as w:
 w.setparams((1,2,16000,0,'NONE','not compressed'));w.writeframes(np.rint(audio.astype(np.float64)*32767).astype('<i2').tobytes())
assert 16000<=len(audio)<=480000 and len(native_pitch)==len(list(plan(len(audio)))) and all(len(x)==923 for x in native_pitch)
assert np.isfinite(audio).all() and np.abs(audio).max()<=1
encoder=HubertEncoder(base/'RVC/assets/hubert_base')
index=EvaluationIndex(candidate/'Mp226.index',INDEX_HASH) if rate else None
runtime=None
from tools.rvc_phase_precision import promote_phase_sum
names=['phone','lengths','pitch','pitchf','speaker','latent_noise','phase_noise','excitation_noise']
errors=[];reference_cores=[];case_chunks=[];chunk_id=0
def synth(padded):
 global chunk_id,runtime
 assert hashlib.sha256(padded.tobytes()).hexdigest()==manifest['windowSHA256'][chunk_id]
 features=encoder.extract(padded)[0]
 if rate:
  found=index.search(features)
  weights=(1/found['distances'])**2;weights/=weights.sum(axis=1,keepdims=True)
  mixed=(found['vectors']*weights[:,:,None]).sum(axis=1)*rate+features*(1-rate)
 else:mixed=features.copy()
 pitch=np.asarray(native_pitch[chunk_id],dtype=np.float64)
 (out/(pitch_mode+'-pitch-'+str(chunk_id)+'.json')).write_text(json.dumps(pitch.tolist()))
 voiced=pitch>0
 if voiced.any():pitch[~voiced]=np.interp(np.flatnonzero(~voiced),np.flatnonzero(voiced),pitch[voiced])
 mel=1127*np.log1p(pitch/700);lo=1127*np.log1p(50/700);hi=1127*np.log1p(1100/700)
 coarse=np.rint(np.clip(np.where(mel>0,(mel-lo)*254/(hi-lo)+1,mel),1,255)).astype(np.int64)[:922]
 pitchf=pitch[:922].astype(np.float32);mask=np.where(pitchf<1,.33,1).astype(np.float32)[:,None]
 prepared=np.repeat(mixed,2,axis=0)*mask+np.repeat(features,2,axis=0)*(1-mask)
 args=(torch.from_numpy(prepared[None,:]),torch.tensor([922]),torch.from_numpy(coarse[None,:]),torch.from_numpy(pitchf[None,:]),torch.tensor([0]))
 torch.manual_seed(347+chunk_id)
 with torch.inference_mode(),_capture_random(torch) as draws:reference=net.infer(*args)[0].numpy()
 explicit=args+tuple(value for kind,value in draws)
 if runtime is None:
  exported=candidate/'synthesizer-precise.onnx'
  proof=candidate/'onnx-export.json'
  if not exported.exists():
   with torch.inference_mode():
    torch.onnx.export(adapter,explicit,str(candidate/'synthesizer.onnx'),export_params=True,opset_version=17,input_names=names,output_names=['audio'],dynamic_axes=None,do_constant_folding=True,dynamo=False)
   original_hash=hashlib.sha256((candidate/'synthesizer.onnx').read_bytes()).hexdigest()
   change=promote_phase_sum(candidate/'synthesizer.onnx',original_hash,exported)
   proof.write_text(json.dumps(dict(sourceModelSHA256=MODEL_HASH,sourceRevision='81eed5e8f68b6bed1789f682fe78cdd324495afc',sourceFiles=SOURCE_HASHES,change=change),indent=2))
  meta=json.loads(proof.read_text());assert meta['sourceModelSHA256']==MODEL_HASH
  runtime=RVCSynthesizer(exported,meta['change']['outputSHA256'],frames=922)
  progress('export-loaded',onnxSHA256=meta['change']['outputSHA256'])
 result=runtime.run({n:t.numpy() for n,t in zip(names,explicit)})
 diff=result.astype(np.float64)-reference
 error=dict(maxAbs=float(np.abs(diff).max()),rms=float(np.sqrt(np.mean(diff*diff))))
 if error['maxAbs']>2e-4 or error['rms']>2e-5:raise ValueError(error)
 errors.append(error);reference_cores.append(reference[0,0,40000:40000+case_chunks[chunk_id].count].copy())
 progress('chunk-passed',chunk=chunk_id,**error);chunk_id+=1
 return result[0,0]
reports=[];mode_outputs={}
for pitch_mode in ('native',):
 repeats=1
 signal=np.tile(audio,repeats);case_chunks=list(plan(len(signal)));chunk_id=0;reference_cores=[];errors=[];pieces=[]
 convert(len(signal),lambda indices:signal[indices],synth,lambda value:pieces.append(value.copy()))
 actual=np.concatenate(pieces);target=(len(signal)*5+1)//2
 # Independent full-buffer weighted oracle for reference synthesis.
 oracle=np.zeros(target,np.float64);denominator=np.zeros(target,np.float64)
 for i,(c,values) in enumerate(zip(case_chunks,reference_cores)):
  weight=np.ones(c.count,np.float64)
  if i:weight[:8000]=np.linspace(0,1,8000,dtype=np.float32)
  if i+1<len(case_chunks):weight[-8000:]=1-np.linspace(0,1,8000,dtype=np.float32)
  oracle[c.start:c.start+c.count]+=values*weight;denominator[c.start:c.start+c.count]+=weight
 if not np.all(denominator>0):raise ValueError('Dropped samples')
 oracle/=denominator
 difference=actual.astype(np.float64)-oracle
 if len(actual)!=target or np.max(np.abs(difference))>2e-4:raise ValueError('Reconstruction mismatch')
 if np.abs(actual).max()>=1:raise ValueError('Would clip PCM')
 name='converted-'+pitch_mode+'.wav'
 mode_outputs[pitch_mode]=actual.copy()
 with wave.open(str(out/name),'wb') as w:
  w.setparams((1,2,40000,0,'NONE','not compressed'));w.writeframes(np.rint(actual*32767).astype('<i2').tobytes())
 seams=[c.start for c in case_chunks[1:]]
 report=dict(pitchMode=pitch_mode,repetitions=repeats,fixtureAssembly='Preselected LibriSpeech test-clean full reference-transcribed utterance '+case_name+'; native prepared audio and default pitch',input16kSamples=len(signal),chunks=len(case_chunks),outputSamples=len(actual),outputSeconds=len(actual)/40000,tailCovered=True,perChunkParity=errors,reconstructionMaxAbs=float(np.max(np.abs(difference))),outputRMS=float(np.sqrt(np.mean(actual.astype(np.float64)**2))),largestAdjacentSampleJump=float(np.abs(np.diff(actual)).max()),overlapStartJumps=[float(abs(actual[p]-actual[p-1])) for p in seams],outputSHA256=hashlib.sha256((out/name).read_bytes()).hexdigest())
 reports.append(report);progress('case-passed',report=report)
encoder.close();runtime.close()
_snapshot(candidate/'Mp226.pth',MODEL_HASH)
comparison=dict(retrievalRate=rate,pitch='Fixed default native pitch; rates 0 and .125 selected before scoring',perceptualQualityClaim=False)
report=dict(nativeExportProvenance=manifest,retrievalAblation=comparison,sparseRetrievalPolicy='Matching VCTK index nprobe=1; exact bounded fallback only for missing neighbors; isolated CPU evaluation above production cap',status='passed',cases=reports,modelSHA256=MODEL_HASH,indexSHA256=INDEX_HASH if rate else None,inputSHA256=manifest['inputSHA256'],pitchMethod='Default native pitch; fixed model, input and random inputs',humanSpeechQualityVerified=False,profileFrames=922,coreSeconds=6,overlapSeconds=.2,maximumAdmittedHours=2,physicalIPhoneVerified=False,qualityReviewed=False,identityVerified=False,published=False,seconds=time.monotonic()-started)
(out/'result.json').write_text(json.dumps(report,indent=2)+'\n');progress('all-passed',report=report)