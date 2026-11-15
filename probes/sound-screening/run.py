"""Compare window lengths at fixed 0.5-second hop; do not alter production source."""
import json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);source=pathlib.Path('VoiceMatrix/LocalSoundQuality.swift').read_text()
manifest=json.loads((root/'manifest.json').read_text());results=[]
for window in [1,2,3]:
 folder=root/('window-'+str(window));folder.mkdir()
 old='let window=min(3.0,seconds)\n                    request.windowDuration=CMTime(seconds:window,preferredTimescale:48_000)\n                    request.overlapFactor=1 - 0.5/window'
 assert source.count(old)==1
 candidate=source.replace(old,f'let window=min({window}.0,seconds)\n                    request.windowDuration=CMTime(seconds:window,preferredTimescale:48_000)\n                    request.overlapFactor=1 - 0.5/window')
 swift=folder/'LocalSoundQuality.swift';swift.write_text(candidate)
 binary=folder/'probe'
 subprocess.run(['swiftc','-parse-as-library',str(swift),'VoiceMatrix/LocalSoundQualityPolicy.swift','probes/sound-screening/Probe.swift','-o',str(binary)],check=True,timeout=120)
 for case in manifest:
  evidence=folder/(case['file']+'.json')
  subprocess.run(['sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary),str(root/case['file']),str(evidence)],check=True,timeout=45)
  d=json.loads(evidence.read_text())
  assert d['sourceSHA256']==case['sha256']
  results.append(dict(windowSeconds=window,file=case['file'],label=case['label'],expected=case['expected'],**d['decision']))
 (root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
 rows=[r for r in results if r['windowSeconds']==window]
 print(json.dumps(dict(window=window,speechAdmitted=sum(r['expected'] and r['admitted'] for r in rows),speechTotal=sum(r['expected'] for r in rows),unsuitableAdmitted=sum(not r['expected'] and r['admitted'] for r in rows),unsuitableTotal=sum(not r['expected'] for r in rows))),flush=True)

assert all(r["admitted"] == r["expected"] for r in results if r["windowSeconds"] == 3), "Three-second validation failed; inspect every preserved result"
