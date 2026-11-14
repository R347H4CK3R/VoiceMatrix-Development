"""Offline automated diagnostics, not human intelligibility or identity verification."""
import pathlib,sys,os,json,hashlib,wave,math,re,gc
r=pathlib.Path(__file__).parent
sys.path[:0]=[str(r/'deps-vctk-decode'),str(r/'deps-long')]
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',OMP_NUM_THREADS='2',CUDA_VISIBLE_DEVICES='')
import numpy as np,torch
from scipy.signal import resample_poly
from transformers import WhisperProcessor,WhisperForConditionalGeneration,AutoFeatureExtractor,WavLMForXVector
torch.set_num_threads(2);torch.set_num_interop_threads(1)
root=r/'objective-evaluation-01'
manifest=json.loads((root/'model-provenance.json').read_text())
for folder,m in manifest.items():
 for name,digest in m['files'].items():
  assert hashlib.sha256((root/folder/name).read_bytes()).hexdigest()==digest
def load(path):
 with wave.open(str(path)) as w:
  assert w.getsampwidth()==2 and w.getnchannels()==1
  rate=w.getframerate();a=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32)/32768
 g=math.gcd(rate,16000);a=resample_poly(a,16000//g,rate//g).astype(np.float32)
 assert 16000<=len(a)<=480000 and np.isfinite(a).all()
 return a
def edits(a,b):
 a=re.findall(r"[a-z0-9']+",a.lower());b=re.findall(r"[a-z0-9']+",b.lower())
 row=list(range(len(b)+1))
 for i,x in enumerate(a,1):
  nxt=[i]
  for j,y in enumerate(b,1):nxt.append(min(nxt[-1]+1,row[j]+1,row[j-1]+(x!=y)))
  row=nxt
 return dict(referenceTokens=len(a),hypothesisTokens=len(b),wordEdits=row[-1],normalizedDisagreement=row[-1]/len(a) if a else None)

import soundfile as sf
candidate=r/'candidate-vctk-p226'
target_path=candidate/'p226.flac'
assert hashlib.sha256(target_path.read_bytes()).hexdigest()=='8a2b79d681c4a143cb923b2e01ca57111991a243e901b1478e7b93d0ff781b97'
references={}
with sf.SoundFile(target_path) as f:
 assert f.channels==1
 for offset in (0,20,40):
  f.seek(int(offset*f.samplerate));a=f.read(int(10*f.samplerate),dtype='float32')
  assert len(a)==10*f.samplerate
  g=math.gcd(f.samplerate,16000)
  references[str(offset)]=resample_poly(a,16000//g,f.samplerate//g).astype(np.float32)
cases={}
for name in ('468c','4b13'):
 cases[name]={'input':r/('objective-'+name)/'prepared-input.wav',
  'oldNoIndex':r/('retrieval-'+name+'-0' if name=='468c' else 'objective-4b13-noindex')/'converted-native.wav',
  'candidateNoIndex':candidate/('conversion-'+name)/'converted-native.wav'}
out=candidate/'objective-evaluation.json'
assert not out.exists()
records={};audios={}
processor=WhisperProcessor.from_pretrained(root/'whisper',local_files_only=True)
model=WhisperForConditionalGeneration.from_pretrained(root/'whisper',local_files_only=True,attn_implementation='eager').eval()
for name,paths in cases.items():
 records[name]={};audios[name]={}
 for kind,path in paths.items():
  a=load(path);audios[name][kind]=a
  v=processor(a,sampling_rate=16000,return_tensors='pt',return_attention_mask=True)
  with torch.inference_mode():tokens=model.generate(input_features=v.input_features,attention_mask=v.attention_mask,do_sample=False,num_beams=1,max_new_tokens=128,forced_decoder_ids=None)
  transcript=processor.batch_decode(tokens,skip_special_tokens=True)[0].strip()
  records[name][kind]=dict(transcript=transcript,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),samples16k=len(a))
  print(json.dumps(dict(stage='asr',case=name,kind=kind,text=transcript)),flush=True)
del processor,model;gc.collect()
processor=AutoFeatureExtractor.from_pretrained(root/'speaker',local_files_only=True)
model=WavLMForXVector.from_pretrained(root/'speaker',local_files_only=True,attn_implementation='eager',weights_only=True).eval()
def embed(a):
 v=processor(a,sampling_rate=16000,return_tensors='pt',padding=True)
 with torch.inference_mode():e=torch.nn.functional.normalize(model(**v).embeddings,dim=-1)[0].numpy()
 assert np.isfinite(e).all()
 return e
anchors={k:embed(a) for k,a in references.items()}
centroid=np.mean(list(anchors.values()),axis=0);centroid/=np.linalg.norm(centroid)
metrics={}
for name,signals in audios.items():
 metrics[name]={}
 for kind,a in signals.items():
  e=embed(a)
  metrics[name][kind]=dict(asrDisagreementVsInput=edits(records[name]['input']['transcript'],records[name][kind]['transcript']),targetCentroidCosine=float(np.dot(e,centroid)),targetAnchorCosines={k:float(np.dot(e,v)) for k,v in anchors.items()})
 print(json.dumps(dict(stage='metrics',case=name,result=metrics[name])),flush=True)
report=dict(modelProvenance=json.loads((candidate/'provenance.json').read_text()),evaluatorModels=manifest,records=records,metrics=metrics,targetReference=dict(path='p226.flac',offsetSeconds=[0,20,40],durationSecondsEach=10,heldOutFromTraining=False),targetAnchorConsistency={a+'__'+b:float(np.dot(anchors[a],anchors[b])) for a,b in [('0','20'),('0','40'),('20','40')]},retrievalRate=0,pitch='Unchanged current native autocorrelation',inputTranscriptIsGroundTruth=False,wordErrorRateClaim=False,humanListeningVerified=False,physicalIPhoneVerified=False,productionQualified=False,published=False,limitations=['Automated ASR disagreement is not ground-truth WER.','Speaker cosine is uncalibrated; anchors may be training data.','These speech fixtures have been used in prior diagnostics and are not fresh holdouts.','Model and dataset licensing are recorded publisher declarations.'])
out.write_text(json.dumps(report,indent=2)+'\n')
print('evaluation complete',flush=True)
