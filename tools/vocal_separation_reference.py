"""Independent NumPy FFT + actual pinned ONNX reference. Test fixtures only."""
import argparse,hashlib,json,pathlib,subprocess
import numpy as np
from tools.prepare_vocal_separation import validate,MODELS
RATE=44100;N=4096;HOP=1024;MAX_FRAMES=441000

def prepare(left,right):
 channels=np.asarray([left,right],dtype=np.float32)
 if channels.ndim!=2 or channels.shape[0]!=2 or not 1<=channels.shape[1]<=MAX_FRAMES or not np.isfinite(channels).all() or np.max(np.abs(channels))>1:raise ValueError('Bounded stereo required')
 original=channels.shape[1]
 padded=np.pad(channels,((0,0),(N,N)))
 tail=(-(padded.shape[1]-N))%HOP
 padded=np.pad(padded,((0,0),(0,tail)))
 count=1+(padded.shape[1]-N)//HOP
 window=0.5-0.5*np.cos(2*np.pi*np.arange(N)/N)
 frames=np.stack([padded[:,i*HOP:i*HOP+N] for i in range(count)],axis=1).astype(np.float64)
 spectra=np.fft.rfft(frames*window,axis=-1)
 magnitude=np.zeros((2,1,512,1024),dtype=np.float32)
 magnitude[:,0,:count,:]=np.abs(spectra[:,:,:1024])
 return magnitude,spectra,window,original

def reconstruct(spectra,window,original,vocals,accompaniment):
 denominator=vocals.astype(np.float64)**2+accompaniment.astype(np.float64)**2+1e-10
 outputs=[];count=spectra.shape[1];length=N+(count-1)*HOP
 for prediction in [vocals,accompaniment]:
  mask=(prediction.astype(np.float64)**2+5e-11)/denominator
  masked=np.zeros_like(spectra);masked[:,:,:1024]=spectra[:,:,:1024]*mask[:,0,:count,:]
  frames=np.fft.irfft(masked,n=N,axis=-1)*window
  result=np.zeros((2,length));weight=np.zeros(length)
  for i in range(count):
   result[:,i*HOP:i*HOP+N]+=frames[:,i,:]
   weight[i*HOP:i*HOP+N]+=window**2
  result[:,weight>0]/=weight[weight>0]
  outputs.append(result[:,N:N+original].astype(np.float32))
 return outputs

def separate(models,left,right):
 import onnxruntime as ort
 validate(models)
 x,spec,window,original=prepare(left,right)
 options=ort.SessionOptions();options.intra_op_num_threads=2
 predictions=[]
 for name in ['vocals.onnx','accompaniment.onnx']:
  session=ort.InferenceSession(str(models/name),sess_options=options,providers=['CPUExecutionProvider'])
  predictions.append(session.run(['y'],{'x':x})[0])
  del session
 if any(p.shape!=x.shape or not np.isfinite(p).all() or np.min(p)<0 for p in predictions):raise ValueError('Invalid model output')
 return reconstruct(spec,window,original,*predictions),x,predictions

def fixtures(models,output):
 source=pathlib.Path(__file__).resolve().parents[1]/'tests/fixtures/licensed-human-source/4507-16021-0031.flac'
 # Fixed first four seconds of complete licensed speech, not an optimized crop.
 decoded=subprocess.check_output(['ffmpeg','-v','error','-i',str(source),'-t','4','-f','f32le','-ac','1','-ar',str(RATE),'-'])
 speech=np.frombuffer(decoded,dtype='<f4').copy();speech*=0.35/max(float(np.max(np.abs(speech))),1e-8)
 t=np.arange(len(speech))/RATE
 # Known deterministic instrumental surrogate; never call this a singing benchmark.
 backing=(0.11*np.sin(2*np.pi*220*t)+0.06*np.sin(2*np.pi*330*t)+0.035*np.sin(2*np.pi*440*t))*(0.65+0.35*np.cos(2*np.pi*1.4*t))
 left=(speech+backing).astype(np.float32);right=(speech*0.85-backing*0.7).astype(np.float32)
 stems,x,pred=separate(models,left,right)
 output.mkdir(parents=True,exist_ok=False)
 arrays={'left':left,'right':right,'speech':speech,'backing':backing.astype(np.float32),'magnitude':x,'prediction-vocals':pred[0],'prediction-accompaniment':pred[1],
         'vocals-left':stems[0][0],'vocals-right':stems[0][1],'accompaniment-left':stems[1][0],'accompaniment-right':stems[1][1]}
 inventory={}
 for name,array in arrays.items():
  data=np.asarray(array,dtype='<f4').tobytes();(output/(name+'.f32')).write_bytes(data);inventory[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
 report={'frames':len(speech),'sampleRate':RATE,'source':source.name,'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),
         'models':MODELS,'arrays':inventory,'scope':'Fixed licensed speech plus known generated accompaniment; actual neural inference and numerical parity, not singing quality or device performance.',
         'vocalLeftMSEToKnownSpeech':float(np.mean((stems[0][0]-speech)**2)),'mixtureLeftMSEToKnownSpeech':float(np.mean((left-speech)**2)),
         'vocalsRMS':float(np.sqrt(np.mean(stems[0]**2))),'accompanimentRMS':float(np.sqrt(np.mean(stems[1]**2)))}
 (output/'reference.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--models',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();fixtures(a.models,a.output)
