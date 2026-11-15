import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CandidatePoolTests(unittest.TestCase):
 def test_later_clean_turn_is_reachable_without_expanding_preview_budget(self):
  source='''import Foundation
@main struct Checks { static func main() throws {
 let turns=(0..<10).map { LocalSpeakerPolicy.Segment(speaker:"A",start:Double($0*12),end:Double($0*12)+10-Double($0)*0.1) }
 let legacy=try LocalSpeakerPolicy.speakerWindows(turns,duration:120)[0].windows
 let current=try LocalSpeakerPolicy.speakerWindows(turns,duration:120,candidateLimit:6)[0].windows
 precondition(legacy.count==3 && current.count==6)
 precondition(current.prefix(3).elementsEqual(legacy))
 // Fixed classifier decisions: first three turns contaminated, fourth acceptable.
 let admitted=current.first { $0.start >= 36 && $0.start < 48 }
 precondition(admitted != nil && !legacy.contains(admitted!))
 let overlaps=turns+[LocalSpeakerPolicy.Segment(speaker:"B",start:36,end:46)]
 let safe=try LocalSpeakerPolicy.speakerWindows(overlaps,duration:120,candidateLimit:6)[0].windows
 precondition(safe.allSatisfy { $0.end <= 36 || $0.start >= 46 })
 do { _=try LocalSpeakerPolicy.speakerWindows(turns,duration:120,candidateLimit:100);fatalError("Unbounded pool") } catch LocalSpeakerPolicy.Failure.resourceBound {}
 print("Bounded later-turn recovery and overlap exclusion passed; classifier evidence is synthetic")
}}
'''
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);(p/'Checks.swift').write_text(source)
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/LocalSpeakerPolicy.swift'),str(p/'Checks.swift'),'-o',str(p/'check')],check=True)
   subprocess.run([str(p/'check')],check=True)
 def test_real_migration_validates_legacy_windows_before_expanding(self):
  text=(ROOT/'VoiceMatrix/LocalSpeakerDiarization.swift').read_text()
  # Compile the actual retained-analysis declaration/validator without Apple inference imports.
  declaration='import Foundation\n'+text[text.index('enum LocalSpeakerDiarization {'):text.index('    static func analyze(')]+'}\n'
  check='''import Foundation
@main struct Checks { static func main() throws {
 let turns=(0..<8).map { LocalSpeakerPolicy.Segment(speaker:"A",start:Double($0*12),end:Double($0*12+9)) }
 let paused:[LocalSpeakerPolicy.Segment]=[.init(speaker:"A",start:0,end:2),.init(speaker:"A",start:2.3,end:4.3)]
 let long:[LocalSpeakerPolicy.Segment]=[.init(speaker:"A",start:0,end:15)]
 for segments in [turns,paused,long] {
  for version:Int? in [nil,1,2,3,4] {
   let windows=try LocalSpeakerPolicy.speakerWindows(segments,duration:100,includeFallbacks:(version ?? 1)>=2,joinSameSpeakerPauses:(version ?? 1)>=3,candidateLimit:version==4 ? 6:3)
   let old=LocalSpeakerDiarization.Analysis(modelRevision:"df2625ac79a7ac6b65ad868fee6d80f320da4232",seconds:100,segments:segments,speakerWindows:windows,selectionPolicyVersion:version)
   let upgraded=try LocalSpeakerDiarization.validatedForCurrentPolicy(old)
   let expected=try LocalSpeakerPolicy.speakerWindows(segments,duration:100,candidateLimit:6)
   precondition(upgraded.selectionPolicyVersion==4 && upgraded.speakerWindows==expected)
   if segments.count==8 { precondition(expected[0].windows.count==6) }
   if segments.count==2 { precondition(windows[0].windows.isEmpty == ((version ?? 1)<3)) }
   if segments.count==1 { precondition(windows[0].windows.count == ((version ?? 1)<2 ? 1:3)) }
  }
 }
 let forged=LocalSpeakerDiarization.Analysis(modelRevision:"df2625ac79a7ac6b65ad868fee6d80f320da4232",seconds:100,segments:turns,speakerWindows:[],selectionPolicyVersion:3)
 do { _=try LocalSpeakerDiarization.validatedForCurrentPolicy(forged);fatalError("Forged crop accepted") } catch LocalSpeakerDiarization.Failure.invalidAudio {}
 print("Actual retained-analysis migration passed for nil/1/2/3/4; forged crops rejected")
}}
'''
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);(p/'Analysis.swift').write_text(declaration);(p/'Check.swift').write_text(check)
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/LocalSpeakerPolicy.swift'),str(p/'Analysis.swift'),str(p/'Check.swift'),'-o',str(p/'check')],check=True)
   subprocess.run([str(p/'check')],check=True)
 def test_studio_keeps_three_generations_and_legacy_analysis_validation(self):
  t=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertIn('if previews >= 3 { break }',t)
  a=(ROOT/'VoiceMatrix/LocalSpeakerDiarization.swift').read_text()
  self.assertIn('candidateLimit:analysis.selectionPolicyVersion == 4 ? 6 : 3',a)
  self.assertIn('selectionPolicyVersion:4',a)
