import pathlib,subprocess,hashlib,json
root=pathlib.Path.cwd();base=root.parent/'rvc-vctk-fresh-20261114'
names=['VoiceMatrix/RVCChunking.swift','VoiceMatrix/RVCFilePreprocessor.swift','VoiceMatrix/RVCFileWorkflow.swift','VoiceMatrix/RVCNativePitch.swift','probes/rvc-long/ExportNativeAudio.swift']
binary=base/'baseline-recompiled'
subprocess.run(['/workspace/shared/swift-recovered/swift-6.1.3-RELEASE-ubuntu22.04/usr/bin/swiftc','-O',*[str(root/n) for n in names],'-o',str(binary)],check=True)
for n in ['4b70','5b55']:
 out=base/n/'baseline-recompiled';out.mkdir()
 subprocess.run([str(binary),str(base/n/'source.wav'),str(out)],check=True)
 assert (out/'prepared.f32').read_bytes()==(base/n/'native/prepared.f32').read_bytes()
 assert json.loads((out/'pitch.json').read_text())==json.loads((base/n/'native/pitch.json').read_text())
report=dict(baselineRecompiled=True,exactPreparedAndPitchMatch=True,cases=['4b70','5b55'],binarySHA256=hashlib.sha256(binary.read_bytes()).hexdigest(),sourceHashes={n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in names})
(base/'native-recompile.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
