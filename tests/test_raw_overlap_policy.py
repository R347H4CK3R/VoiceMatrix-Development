"""Actual Swift boundary proofs plus fail-closed resume wiring guards."""
import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RawOverlapPolicyTests(unittest.TestCase):
 def test_native_policy_boundaries_and_invalid_evidence(self):
  with tempfile.TemporaryDirectory() as d:
   binary=pathlib.Path(d)/'check'
   subprocess.run(['swiftc','-parse-as-library',str(ROOT/'VoiceMatrix/LocalOverlapPolicy.swift'),str(ROOT/'probes/raw-overlap-policy/Tests.swift'),'-o',str(binary)],check=True)
   subprocess.run([str(binary)],check=True)
 def test_current_analysis_requires_raw_evidence_and_exact_veto(self):
  text=(ROOT/'VoiceMatrix/LocalSpeakerDiarization.swift').read_text()
  declaration='import Foundation\n'+text[text.index('enum LocalSpeakerDiarization {'):text.index('    static func analyze(')]+'}\n'
  check='''import Foundation
@main struct Checks {static func main() throws {
 let revision="df2625ac79a7ac6b65ad868fee6d80f320da4232",sha=String(repeating:"a",count:64)
 let segments:[LocalSpeakerPolicy.Segment]=[.init(speaker:"S1",start:0,end:8)]
 let candidates=try LocalSpeakerPolicy.speakerWindows(segments,duration:8,candidateLimit:6)
 let raw=try LocalOverlapPolicy.build(weights:[Array(repeating:[Float(1),Float(1)],count:8)],offsets:[0],frameDuration:1,duration:8,sourceSHA256:sha,modelRevision:revision)
 let safe=try LocalSpeakerDiarization.excludingRawOverlap(candidates,evidence:raw)
 precondition(safe.count==1 && safe[0].windows.isEmpty)
 let valid=LocalSpeakerDiarization.Analysis(modelRevision:revision,seconds:8,segments:segments,speakerWindows:safe,selectionPolicyVersion:5,rawOverlap:raw)
 _=try LocalSpeakerDiarization.validatedForCurrentPolicy(valid)
 let noEvidence=LocalSpeakerDiarization.Analysis(modelRevision:revision,seconds:8,segments:segments,speakerWindows:candidates,selectionPolicyVersion:5)
 let forged=LocalSpeakerDiarization.Analysis(modelRevision:revision,seconds:8,segments:segments,speakerWindows:candidates,selectionPolicyVersion:5,rawOverlap:raw)
 for bad in [noEvidence,forged] {
  do {_=try LocalSpeakerDiarization.validatedForCurrentPolicy(bad);fatalError("Missing/veto-bypassed raw evidence accepted")} catch {}
 }
 var emptyRaw=raw;emptyRaw.counts=[]
 let incomplete=LocalSpeakerDiarization.Analysis(modelRevision:revision,seconds:8,segments:segments,speakerWindows:safe,selectionPolicyVersion:5,rawOverlap:emptyRaw)
 do {_=try LocalSpeakerDiarization.validatedForCurrentPolicy(incomplete);fatalError("Incomplete raw evidence accepted")}catch{}
 print("PASS actual retained-analysis current-policy missing/truncated/forged crop rejection")
}}
'''
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'Analysis.swift').write_text(declaration);(p/'Checks.swift').write_text(check)
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/LocalSpeakerPolicy.swift'),str(ROOT/'VoiceMatrix/LocalOverlapPolicy.swift'),str(p/'Analysis.swift'),str(p/'Checks.swift'),'-o',str(p/'check')],check=True)
   subprocess.run([str(p/'check')],check=True)
 def test_resume_requires_bound_current_evidence_before_reusing_assets(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertLess(s.index('<= 4_000_000'),s.index('JSONDecoder().decode(LocalSpeakerDiarization.Analysis'))
  self.assertIn('validated.selectionPolicyVersion == 5',s)
  self.assertIn('validated.rawOverlap?.sourceSHA256 == expectedHash',s)
  reset=s.index('// Fresh analysis invalidates every job association');save=s.index('current?.analysisFile = name',reset)
  for field in ['speakerVoiceIDs','speakerAssets','speakerOutcomes','qualityPolicyVersions','visualEvidence']:
   self.assertIn('current?.'+field+'=nil',s[reset:save])
  self.assertNotIn('library.remove',s[reset:save]);self.assertNotIn('removeItem',s[reset:save])
  self.assertLess(save,s.index('"Reference already saved"',save))
 def test_native_fresh_analysis_clears_stale_associations_without_metadata(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  start=s.index('                    // Fresh analysis invalidates every job association')
  end=s.index('                    let data = try JSONEncoder().encode(analysis)',start)
  reset=s[start:end]
  self.assertNotIn('if ',reset)
  fields=['speakerVoiceIDs','speakerAssets','speakerOutcomes','qualityPolicyVersions','visualEvidence','referenceFile','previewFile','similarity','voiceID']
  # Execute the exact production reset statements; these opaque values represent
  # already imported assets, not a mocked library deletion or synthesis pipeline.
  decl='\n'.join(' var '+f+': String? = "retained"' for f in fields)
  assertions='\n'.join('precondition(current?.'+f+' == nil)' for f in fields)
  script='''import Foundation
struct Job {
 var analysisFile: String? = nil
 var analysisSHA256: String? = nil
'''+decl+'''
}
@main struct Check { static func main() {
 for missing in 0..<3 {
  var current: Job? = Job()
  if missing == 1 { current?.analysisFile = "old.json" }
  if missing == 2 { current?.analysisSHA256 = "old-digest" }
  let libraryProfiles = ["existing-voice"]
  let retainedFiles = ["reference.wav", "preview.wav"]
'''+reset+assertions+'''
  precondition(libraryProfiles == ["existing-voice"])
  precondition(retainedFiles == ["reference.wav", "preview.wav"])
 }
 print("PASS fresh-analysis reset with missing name/digest/both; no old association reusable")
}}
'''
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'Check.swift').write_text(script)
   subprocess.run(['swiftc','-parse-as-library',str(p/'Check.swift'),'-o',str(p/'check')],check=True)
   subprocess.run([str(p/'check')],check=True)
