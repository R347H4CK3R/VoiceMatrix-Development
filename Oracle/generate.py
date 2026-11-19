"""Independent float64 FFT/mel/math oracle fixtures. No Torch/CoreML imports.
Generated tones/noise are NOT real speech; optional native-synthesized WAV is labeled.
"""
import pathlib,json,hashlib,wave,argparse
import numpy as np
from oracle import features
ROOT=pathlib.Path(__file__).resolve().parent

def make_cases():
    for n in (257,258,319,320,321,399,400,401,511,512,513,15999,16000,16001,239999,240000):
        yield f'tone-{n}',(.1*np.sin(2*np.pi*440*np.arange(n)/16000)).astype(np.float32),n
    for n in (257,400,16000,240000):yield f'silence-{n}',np.zeros(n,dtype=np.float32),n
    for n in (400,16000,240000):
        yield f'near-silence-{n}',(1e-5*np.sin(2*np.pi*440*np.arange(n)/16000)).astype(np.float32),n
        a=np.zeros(n,dtype=np.float32);a[0]=.5;a[-1]=-.5;yield f'edge-impulses-{n}',a,n
    for valid in (160,161,319,320,15999,16000,239999):
        a=np.zeros(240000,dtype=np.float32);a[:valid]=.1*np.sin(2*np.pi*440*np.arange(valid)/16000)
        yield f'padded-valid-{valid}',a,valid
    for valid in (160,16000):
        n=240000;t=np.arange(n)/16000
        a=(.1*np.sin(2*np.pi*440*t)).astype(np.float32)
        a[valid:]=(.04*np.cos(2*np.pi*997*t[valid:])).astype(np.float32)
        yield f'nonzero-tail-valid-{valid}',a,valid
    n=240000;t=np.arange(n)/16000;rng=np.random.default_rng(231)
    envelope=(np.sin(2*np.pi*2*t)**2)*(.3+.7*(np.sin(2*np.pi*.37*t)>-.3))
    a=envelope*(.07*np.sin(2*np.pi*(110*t+20*t*t))+.03*np.sin(2*np.pi*710*t)+.01*rng.standard_normal(n))
    yield 'synthetic-envelope-not-speech-240000',a.astype(np.float32),n

def _buffers():
    arrays=[]
    for name,sha,shape in [('window','744788a137aa808ccc97d9d3c185c649b2e9c2b99c3262887c3ac9bb3b7e1c4c',(400,)),('filterbank','f5608e00763a20a191022fbb00a43346db5f1ec06828a97a6f4157f7d02b76c8',(128,257))]:
        b=(ROOT/'original-buffers'/(name+'.f32le')).read_bytes()
        if hashlib.sha256(b).hexdigest()!=sha:raise ValueError('Buffer digest mismatch')
        arrays.append(np.frombuffer(b,dtype='<f4').reshape(shape))
    return arrays

def write_fixture(dest,name,a,valid):
    w,fb=_buffers();a=np.asarray(a,dtype='<f4');mel,count=features(a,valid,fb,w,160)
    if not np.isfinite(mel).all():raise ValueError('Nonfinite oracle')
    raw_audio=a.tobytes();raw_mel=mel.astype('<f4').tobytes()
    for suffix,b in [('audio',raw_audio),('mel',raw_mel)]:
        with (dest/(name+'.'+suffix+'.f32le')).open('xb') as f:f.write(b)
    return dict(name=name,samples=len(a),validSamples=valid,frames=mel.shape[1],validFrames=count,audioSHA256=hashlib.sha256(raw_audio).hexdigest(),melSHA256=hashlib.sha256(raw_mel).hexdigest())

def speech_cases(path):
    # Explicitly PCM16, mono16k: native say/afconvert can produce this without downloads.
    with wave.open(str(path),'rb') as f:
        if (f.getnchannels(),f.getsampwidth(),f.getframerate(),f.getcomptype())!=(1,2,16000,'NONE'):raise ValueError('Expected mono16k PCM16 WAV')
        if f.getnframes()>16000*120:raise ValueError('Speech over120seconds')
        a=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(np.float32)/32768
    if len(a)<240000:raise ValueError('Speech must contain at least15seconds')
    # Cover longer speech through multiple independently processed15-second windows.
    for start in sorted({0,80000,max(0,len(a)-240000)}):
        x=a[start:start+240000]
        if len(x)==240000:yield f'native-synthetic-speech-offset-{start}',x,len(x)

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--speech-wav',type=pathlib.Path);args=p.parse_args();args.out.mkdir(parents=True,exist_ok=False)
    cases=list(make_cases())
    if args.speech_wav:cases+=list(speech_cases(args.speech_wav))
    names=[x[0] for x in cases]
    if len(names)!=len(set(names)):raise ValueError('Duplicate fixture')
    rows=[write_fixture(args.out,*x) for x in cases]
    (args.out/'fixtures.json').write_text(json.dumps(rows,indent=2))
    (args.out/'oracle-provenance.json').write_text(json.dumps({'numpy':np.__version__,'oracle_sha256':hashlib.sha256((ROOT/'oracle.py').read_bytes()).hexdigest(),'scope':'independent float64 defined math then final float32; not exact original Torch output','real_speech':False,'native_synthesized_speech':bool(args.speech_wav)},indent=2))
    print(len(rows),'fixtures')
if __name__=='__main__':main()
