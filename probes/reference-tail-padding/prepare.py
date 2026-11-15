"""Append only50ms silence to a diagnostic copy; never trim or overwrite source."""
import pathlib,wave,hashlib,json,io,sys
SOURCE_SHA='da2cdba0b9b706dd053fe9e643a941bb99816439ac064a8443f732c6c33270a5'
def prepare(root):
    source=root/'reference.wav';original=source.read_bytes()
    assert hashlib.sha256(original).hexdigest()==SOURCE_SHA
    with wave.open(io.BytesIO(original)) as w:
        assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==24000 and w.getcomptype()=='NONE'
        params=w.getparams();pcm=w.readframes(w.getnframes())
    assert all(not (root/f'reference-tail-{ms}.wav').exists() for ms in [0,50]), "Never overwrite evidence"
    rows=[]
    for milliseconds in [0,50]:
        target=root/f'reference-tail-{milliseconds}.wav'
        assert not target.exists(),'Never overwrite evidence'
        frames=24000*milliseconds//1000
        if milliseconds==0: target.write_bytes(original)
        else:
            with wave.open(str(target),'wb') as w:
                w.setparams(params);w.writeframes(pcm+bytes(frames*2))
        with wave.open(str(target)) as w:
            derived=w.readframes(w.getnframes())
            assert derived[:len(pcm)]==pcm and derived[len(pcm):]==bytes(frames*2)
        rows.append(dict(milliseconds=milliseconds,addedFrames=frames,sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    assert source.read_bytes()==original
    manifest=dict(sourceSHA256=SOURCE_SHA,sourceFrames=len(pcm)//2,rate=24000,variants=rows,
        upstreamDocumentation='https://github.com/SWivid/F5-TTS/blob/600e5fdfbf319f84735557aca80a7aaf60d487e6/src/f5_tts/infer/utils_infer.py',
        scope='Diagnostic append-only tail comparison; upstream also trims edges, which this experiment explicitly does not do.')
    (root/'reference-padding-proof.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest
if __name__=='__main__': prepare(pathlib.Path(sys.argv[1]))
