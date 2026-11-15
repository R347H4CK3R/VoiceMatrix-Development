"""Trace-only copy: never change model output, selection policy or release source."""
import hashlib,json,pathlib,sys
source=pathlib.Path('VoiceMatrix/LocalSpeakerDiarization.swift');target=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);out.mkdir(exist_ok=True)
s=source.read_text();anchor='            let windows = try LocalSpeakerPolicy.speakerWindows(segments,duration:duration,candidateLimit:6)'
assert s.count(anchor)==1
trace='''            let diagnosticSegments = try JSONEncoder().encode(segments)
            try FileHandle.standardError.write(contentsOf:Data(("TRACE decodedDuration=\\(duration) rawSegments=" + String(decoding:diagnosticSegments,as:UTF8.self) + "\\n").utf8))
'''
target.write_text(s.replace(anchor,trace+anchor))
(out/'instrumentation.json').write_text(json.dumps(dict(kind='Trace only before unchanged selection policy',sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),instrumentedSHA256=hashlib.sha256(target.read_bytes()).hexdigest(),modelOutputAltered=False,selectionGatesAltered=False),indent=2))
(out/'instrumented-adapter.swift').write_bytes(target.read_bytes())
