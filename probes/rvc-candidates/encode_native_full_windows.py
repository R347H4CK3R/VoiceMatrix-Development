import pathlib,sys,os,json,hashlib,socket
ROOT=pathlib.Path.cwd()
sys.path[:0]=[str(ROOT/'voicematrix-hubert-deps'),str(ROOT/'voicematrix-unicode-candidate')]
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',OMP_NUM_THREADS='2',CUDA_VISIBLE_DEVICES='')
def offline(*a,**kw):raise RuntimeError('Network disabled in fixture execution')
socket.socket.connect=offline;socket.create_connection=offline
import numpy as np,torch
from tools.rvc_hubert import HubertEncoder
from tools.rvc_chunking import plan,window
torch.set_num_threads(2);torch.set_num_interop_threads(1)
out=ROOT/'rvc-native-full-window-20261115'
encoder=HubertEncoder((ROOT/'voicematrix-hubert-assets').resolve())
for name in ('5683-32865-0017','121-127105-0022'):
 source=ROOT/'rvc-librispeech-broader-v2-20261115'/name/'payload'
 m=json.loads((source/'manifest.json').read_text())
 raw=(source/'prepared.f32').read_bytes();assert hashlib.sha256(raw).hexdigest()==m['files']['prepared.f32']
 audio=np.frombuffer(raw,dtype='<f4');chunks=list(plan(len(audio)));assert len(chunks)==1
 padded=window(len(audio),chunks[0].input_start,lambda ids:audio[ids])
 assert hashlib.sha256(padded.tobytes()).hexdigest()==m['windowSHA256'][0]
 features=encoder.extract(padded)[0];assert features.shape==(461,768)
 folder=out/name;folder.mkdir(exist_ok=False)
 (folder/'features.f32').write_bytes(features.astype('<f4').tobytes())
 (folder/'pitch.json').write_bytes((source/'pitch.json').read_bytes())
 m['featuresSHA256']=hashlib.sha256((folder/'features.f32').read_bytes()).hexdigest()
 (folder/'manifest.json').write_text(json.dumps(m,indent=2))
 print(json.dumps(dict(case=name,rows=461,featuresSHA256=m['featuresSHA256'])),flush=True)
encoder.close()
