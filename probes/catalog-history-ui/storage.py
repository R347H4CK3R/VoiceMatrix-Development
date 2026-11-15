"""Seed/check only this CI-owned simulator, never a connected user device."""
import hashlib,json,os,pathlib,shutil,subprocess,sys,wave,array
mode=sys.argv[1];device=os.environ['SIMULATOR_ID']
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.voicematrix.app','data'],text=True).strip())
assert container.is_dir()
root=container/'Library/Application Support/CatalogSpeechChecks';attempt=root/'A8D5A8AA-2864-4BB3-BF19-AEE5CF424A16'
second=root/'B8D5A8AA-2864-4BB3-BF19-AEE5CF424A16'
source=pathlib.Path('VoiceMatrix/Resources/F5TTS/UITestVoices/diagnostic-neutral/reference.wav');sha=hashlib.sha256(source.read_bytes()).hexdigest()
if mode=='seed':
 assert not attempt.exists();attempt.mkdir(parents=True)
 shutil.copyfile(source,attempt/'speech.wav')
 (attempt/'request.json').write_text(json.dumps(dict(voiceID='diagnostic-neutral',referenceHash=sha,requestedText='Synthetic retained speech UI fixture',controls='UI fixture; not synthesized or verified',created=2)))
 second.mkdir(parents=True)
 with wave.open(str(source)) as w: params=w.getparams();samples=array.array('h',w.readframes(w.getnframes()))
 assert params.sampwidth==2
 samples=array.array('h',(int(v/2) for v in samples))
 with wave.open(str(second/'speech.wav'),'wb') as w:w.setparams(params);w.writeframes(samples.tobytes())
 (second/'request.json').write_text(json.dumps(dict(voiceID='diagnostic-neutral',referenceHash=sha,requestedText='Second retained speech UI fixture',controls='Second synthetic UI fixture',created=1)))
 pathlib.Path('history-fixture-proof.json').write_text(json.dumps(dict(synthetic=True,wordCheckVerified=False,sha256=sha,bytes=source.stat().st_size,attemptID=attempt.name,secondSHA256=hashlib.sha256((second/'speech.wav').read_bytes()).hexdigest(),secondAttemptID=second.name)))
elif mode=='verify':
 assert not attempt.exists() and not second.exists(),'Confirmed UI deletion must remove both fixture history items'
 recordings=list((container/'Documents/Recordings').glob('*.wav'))
 matches=[p for p in recordings if hashlib.sha256(p.read_bytes()).hexdigest()==sha]
 assert len(matches)==1,'Save Recording must copy exact first retained bytes'
 expectedSecond=json.loads(pathlib.Path('history-fixture-proof.json').read_text())['secondSHA256']
 assert expectedSecond!=sha
 assert len([p for p in recordings if hashlib.sha256(p.read_bytes()).hexdigest()==expectedSecond])==1,'Second retained output must be separately saved'
 references=list((container/'Library/Application Support/CharacterReferences').glob('*/reference.wav'))
 assert any(hashlib.sha256(p.read_bytes()).hexdigest()==sha for p in references),'Voice reference must remain'
 pathlib.Path('history-storage-results.json').write_text(json.dumps(dict(exactSavedCopy=True,confirmedHistoryDeleted=True,referenceRetained=True,systemShareDestinationSelected=False,physicalDeviceVerified=False,sha256=sha)))
else:raise ValueError(mode)
