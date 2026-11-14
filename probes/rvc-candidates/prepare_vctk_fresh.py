import pathlib,urllib.request,subprocess,json,hashlib,zipfile,sys
import numpy as np
sys.path.insert(0,str(pathlib.Path.cwd()))
from tools.rvc_chunking import plan,window
root=pathlib.Path.cwd();out=root.parent/'rvc-vctk-fresh-20261114';out.mkdir(exist_ok=False)
swift='/workspace/shared/swift-recovered/swift-6.1.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
sources=[root/'VoiceMatrix/RVCChunking.swift',root/'VoiceMatrix/RVCFilePreprocessor.swift',root/'VoiceMatrix/RVCFileWorkflow.swift',root/'probes/rvc-long/ExportNativeAudio.swift']
candidate=out/'candidate-export'
subprocess.run([swift,'-O',*map(str,sources),str(root/'probes/rvc-long/pitch-variants/rvc_ac_sinc32.swift'),'-o',str(candidate)],check=True)
provenance=[]
for name in ['4b70','5b55']:
 p=out/name;p.mkdir();url='https://huggingface.co/kyutai/tts-voices/resolve/323332d33f997de8394f24a193e1a76df720e01a/voice-donations/'+name+'.wav'
 with urllib.request.urlopen(url,timeout=60) as f:(p/'source.wav').write_bytes(f.read(1000001))
 expected={'4b70':'d3d3d29e90eadae84ab3641a46aff7323617a4990d3a7abfe398e8b0fc802119','5b55':'54ea36e1fa64d917a69ebe3f80a3ffea8709ca37d7634f21fc70d421bbde7e05'}
 assert hashlib.sha256((p/'source.wav').read_bytes()).hexdigest()==expected[name]
 for method,binary in [('native',root.parent/'rvc-export-native-audio'),('sinc32',candidate)]:
  dest=p/method;dest.mkdir();subprocess.run([str(binary),str(p/'source.wav'),str(dest)],check=True)
 a=(p/'native/prepared.f32').read_bytes();assert a==(p/'sinc32/prepared.f32').read_bytes()
 signal=np.frombuffer(a,dtype='<f4')
 payload=p/'payload';payload.mkdir()
 for dest,data in [('prepared.f32',a),('pitch.json',(p/'native/pitch.json').read_bytes()),('sinc32.json',(p/'sinc32/pitch.json').read_bytes()),('native-result.json',(p/'native/native-result.json').read_bytes())]:(payload/dest).write_bytes(data)
 manifest=dict(inputName=name+'.wav',inputSHA256=hashlib.sha256((p/'source.wav').read_bytes()).hexdigest(),url=url,license='CC0-1.0',revision='323332d33f997de8394f24a193e1a76df720e01a',selection='Next two original (non-enhanced) filenames after 4b13, selected before this evaluation',files={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in payload.iterdir()},windowSHA256=[hashlib.sha256(window(len(signal),c.input_start,lambda ids:signal[ids]).tobytes()).hexdigest() for c in plan(len(signal))],sourceHashes={'native':hashlib.sha256((root/'VoiceMatrix/RVCNativePitch.swift').read_bytes()).hexdigest(),'sinc32':hashlib.sha256((root/'probes/rvc-long/pitch-variants/rvc_ac_sinc32.swift').read_bytes()).hexdigest()})
 (payload/'manifest.json').write_text(json.dumps(manifest,indent=2));provenance.append(manifest)
with zipfile.ZipFile(out/'payloads.zip','x',zipfile.ZIP_DEFLATED) as z:
 for name in ['4b70','5b55']:
  for f in (out/name/'payload').iterdir():z.write(f,name+'/'+f.name)
(out/'inputs.json').write_text(json.dumps(provenance,indent=2)+'\n')
print(json.dumps(dict(zip=str(out/'payloads.zip'),bytes=(out/'payloads.zip').stat().st_size,sha256=hashlib.sha256((out/'payloads.zip').read_bytes()).hexdigest())))
