"""Bind independent final-wave ASR to untouched shipping sources and exact outcomes."""
import hashlib,json,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE_PINS={'OnDeviceTranscription.swift':'758ed706e92fc3da63cdfb6048fb65afcd13475ece8534381bbd2f0050e06ae6','BundledASRAssets.swift':'de6d3d258d77fb8042d16de524b128c98f140bee46e327616cf971432534bcfb','BundledASRPolicy.swift':'ce50e078dfae0285efc4c574f88faea115ef0e1fdef1e0de9d75b8cebbe19d70','LocalStudioEvidence.swift':'3a19d0a8d021406a2ea1777c107a12882a48969dcf1f06f5ecac4ad1eb1c63f7'}
def validate(root,report):
 root=pathlib.Path(root);rows=report['newSpeeches'];ids=report['importedIDs']
 if len(rows)!=2 or len(ids)!=2 or len(set(ids))!=2 or {r['voiceID'] for r in rows}!=set(ids):raise ValueError('Require two distinct imported voices')
 result=[];names=set()
 for r in rows:
  name=r['file'];sha=r['newSpeechSHA256']
  if re.fullmatch(r'[A-Za-z0-9_-]+\.wav',name) is None or name in names or re.fullmatch('[a-f0-9]{64}',sha) is None:raise ValueError('Unsafe or repeated final filename')
  names.add(name);p=root/'work'/name
  if (root/'work').is_symlink() or p.is_symlink() or not p.is_file() or p.stat().st_size>8_388_608 or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:raise ValueError('Final WAV identity mismatch')
  result.append(dict(voiceID=r['voiceID'],file=name,sha256=sha,expected='Please close the window and bring the notebook.'))
 return result

def main():
 root=pathlib.Path(sys.argv[1]);out=root/'unpadded-verification';out.mkdir(exist_ok=False)
 try:
  inputs=validate(root,json.loads((root/'pipeline-evidence.json').read_text()))
  target=ROOT/'probes/leading-padding-unpadded-verifier/Sources/Probe'
  for name,sha in SOURCE_PINS.items():
   p=(ROOT/'probes/leading-padding-unpadded-verifier/Baseline'/name) if name in ('OnDeviceTranscription.swift','BundledASRPolicy.swift') else ROOT/'VoiceMatrix'/name;data=p.read_bytes()
   if p.is_symlink() or hashlib.sha256(data).hexdigest()!=sha:raise ValueError('Independent build10 ASR baseline drift')
   with (target/name).open('xb') as f:f.write(data)
  (out/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
  (out/'source-proof.json').write_text(json.dumps(dict(sourceHashes=SOURCE_PINS,scope='Independent pinned build10 ASR baseline verifies exact final WAVs; reference-only context candidate; final playback WAVs are never padded by this verifier.'),indent=2)+'\n')
 except Exception as e:
  (out/'stage-error.json').write_text(json.dumps(dict(error=str(e))))
  raise
if __name__=='__main__':main()
