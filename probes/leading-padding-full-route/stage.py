"""Fixed 250 ms leading silence experiment. Never modifies shipping sources."""
import difflib, hashlib, json, pathlib
SOURCE_SHA='758ed706e92fc3da63cdfb6048fb65afcd13475ece8534381bbd2f0050e06ae6'
PATCHED_SHA='6ac28ad0676739bb1af53c271e1b42c21c6360755ca4c0c2404da6042b5a7377'
PROJECT_SHA='ed81861c9e5faf662755d631c97ea29ce81931f66f830455b4f6c47fd6d7c1e4'
OLD=b'var result = try await manager.transcribe(file, decoderState: &decoder)'
NEW=b'var result = try await manager.transcribe(try diagnosticLeadingBuffer(file), decoderState: &decoder)'
HELPER=b'''    // Diagnostic only: fixed silence, no text, prompts, decoder or confidence changes.
    private nonisolated static func diagnosticLeadingBuffer(_ file: URL) throws -> AVAudioPCMBuffer {
        try Task.checkCancellation()
        let audio = try AVAudioFile(forReading: file)
        let rate = audio.processingFormat.sampleRate
        guard rate.isFinite, (16000...48000).contains(rate), audio.processingFormat.channelCount == 1,
              audio.length > 0, Double(audio.length) / rate + 0.25 <= 30,
              let original = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else { throw Failure.invalidAudio }
        try audio.read(into: original)
        guard original.frameLength == AVAudioFrameCount(audio.length), let input = original.floatChannelData?[0] else { throw Failure.invalidAudio }
        let lead = AVAudioFrameCount((rate * 0.25).rounded())
        let total = original.frameLength + lead
        guard let padded = AVAudioPCMBuffer(pcmFormat: original.format, frameCapacity: total), let output = padded.floatChannelData?[0] else { throw Failure.invalidAudio }
        padded.frameLength = total
        output.initialize(repeating: 0, count: Int(lead))
        output.advanced(by: Int(lead)).update(from: input, count: Int(original.frameLength))
        try Task.checkCancellation()
        return padded
    }

'''
ANCHOR=b'    private nonisolated static func recoveryBuffer('
OLD_PATH=b'    - path: VoiceMatrix/OnDeviceTranscription.swift'
NEW_PATH=b'    - path: padding-staged/OnDeviceTranscription.swift'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def patch(raw):
 if sha(raw)!=SOURCE_SHA or raw.count(OLD)!=1 or raw.count(ANCHOR)!=1:raise ValueError('Recognizer source drift')
 result=raw.replace(OLD,NEW).replace(ANCHOR,HELPER+ANCHOR)
 if sha(result)!=PATCHED_SHA:raise ValueError('Diagnostic patch drift')
 return result
def project(raw):
 if sha(raw)!=PROJECT_SHA:raise ValueError('Project source drift')
 # Select only this diagnostic target; never change the app or other test hosts.
 start=raw.index(b'  LocalStudioDiagnostic:\n');end=raw.index(b'\nschemes:',start)
 target=raw[start:end]
 if target.count(OLD_PATH)!=1:raise ValueError('Unexpected diagnostic target')
 return raw[:start]+target.replace(OLD_PATH,NEW_PATH)+raw[end:]
def stage(root):
 root=pathlib.Path(root);src=root/'VoiceMatrix/OnDeviceTranscription.swift';spec=root/'project.yml'
 if src.is_symlink() or spec.is_symlink():raise ValueError('Linked source')
 raw=src.read_bytes();modified=patch(raw);configured=project(spec.read_bytes())
 out=root/'padding-staged';out.mkdir(exist_ok=False)
 (out/'OnDeviceTranscription.swift').write_bytes(modified)
 (out/'patch.diff').write_text(''.join(difflib.unified_diff(raw.decode().splitlines(True),modified.decode().splitlines(True),fromfile='shipping/OnDeviceTranscription.swift',tofile='diagnostic/OnDeviceTranscription.swift')))
 # The generated spec must remain at root so relative source paths remain exact.
 destination=root/'diagnostic-leading.yml'
 with destination.open('xb') as f:f.write(configured)
 (out/'staging-proof.json').write_text(json.dumps(dict(shippingSourceSHA256=sha(raw),diagnosticSourceSHA256=sha(modified),projectSHA256=PROJECT_SHA,diagnosticProjectSHA256=sha(configured),leadingSeconds=.25,productionChange=False,physicalDeviceVerified=False,scope='Fixed input-buffer silence diagnostic only; original WAV hashes retained; no prompt, transcript, threshold or decoder change.'),indent=2)+'\n')
 if src.read_bytes()!=raw:raise ValueError('Shipping source changed')
if __name__=='__main__':stage(pathlib.Path(__file__).resolve().parents[2])
