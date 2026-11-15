import pathlib,sys,hashlib,json,wave,time,socket,importlib.metadata,os,argparse
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=pathlib.Path,required=True)
parser.add_argument('--audio-root',type=pathlib.Path,required=True)
args=parser.parse_args()
R=args.output
R.mkdir(exist_ok=True)
if any((R/name).exists() for name in ('result.json','silence.wav','assembledABA.wav')):
 raise RuntimeError('Refusing to overwrite prior evidence')
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[2]))
os.environ.update(OMP_NUM_THREADS='2',MKL_NUM_THREADS='2',OPENBLAS_NUM_THREADS='2',HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1')
def deny(*a,**k):raise RuntimeError('Network blocked during inference')
socket.socket.connect=deny;socket.socket.connect_ex=deny;socket.create_connection=deny
from tools import speaker_candidates as sc
paths=[args.audio_root/n/'source.wav' for n in ['2961-960-0003','4507-16021-0031']]
pcms=[];sources=[]
for p in paths:
 with wave.open(str(p)) as f:
  assert (f.getnchannels(),f.getsampwidth(),f.getframerate())==(1,2,16000)
  pcm=f.readframes(f.getnframes());pcms.append(pcm)
 sources.append(dict(id=p.parent.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),seconds=len(pcm)/32000))
def save(name,pcm):
 p=R/(name+'.wav')
 with wave.open(str(p),'wb') as f:f.setparams((1,2,16000,0,'NONE','none'));f.writeframes(pcm)
 return p
silence=b'\0\0'*16000
cases={'silence':save('silence',silence*8),'speakerA':paths[0],'speakerB':paths[1],'assembledABA':save('assembledABA',pcms[0]+silence+pcms[1]+silence+pcms[0])}
a=sources[0]['seconds'];b=sources[1]['seconds']
truth=[dict(speaker='A',start=0,end=a),dict(speaker='B',start=a+1,end=a+1+b),dict(speaker='A',start=a+b+2,end=2*a+b+2)]
report=dict(scope='Real LibriSpeech speech; assembled A-B-A turns with known boundaries, not natural conversation; repeated A is the same utterance',sources=sources,truth=truth,networkBlocked=True,moduleSHA256=hashlib.sha256(pathlib.Path(sc.__file__).read_bytes()).hexdigest(),modelSHA256=sc.MODEL_SHA256,vadSHA256=sc.VAD_SHA256,versions={n:importlib.metadata.version(n) for n in ['torch','torchaudio','speechbrain','silero-vad','onnxruntime','numpy','scikit-learn']},cases={})
start=time.monotonic();model=sc.load_local_encoder(R/'embedding_model.ckpt',R/'silero_vad.onnx');report['loadSeconds']=time.monotonic()-start
for name,p in cases.items():
 start=time.monotonic();r=sc.analyze(p,model);r['elapsedSeconds']=time.monotonic()-start
 r['sourceSHA256']=hashlib.sha256(p.read_bytes()).hexdigest();report['cases'][name]=r
 print(name,'groups',len(r['candidates']),'windows',r['analyzedWindows'],'omitted',r['omittedCount'],flush=True)
 (R/'result.json').write_text(json.dumps(report,indent=2))
print('complete',flush=True)
