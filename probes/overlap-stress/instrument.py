"""Diagnostic-only copied vendor instrumentation; original vendor remains immutable."""
import difflib,hashlib,json,pathlib,shutil
root=pathlib.Path.cwd();original=root/'Vendors/FluidAudio';copy=root/'diagnostic-vendor/FluidAudio'
if copy.exists():raise FileExistsError(copy)
shutil.copytree(original,copy)
relative='Sources/FluidAudio/Diarizer/Offline/Utils/OfflineReconstruction.swift';src=original/relative;dst=copy/relative
before=src.read_text();assert hashlib.sha256(src.read_bytes()).hexdigest()=='d5b9f2532ecb3c5d40cb621f83ea2768a5cab56d6817c9123dc987b67b6d2c54'
needle='        if !speakerCountHistogram.isEmpty {'
assert before.count(needle)==1
addition='''        // Diagnostic-only numeric observation, after existing post-clamp decisions.
        let diagnosticCounts = expectedCountSums.enumerated().map { index, value in
            expectedCountWeights[index] > 0 ? value / expectedCountWeights[index] : -1.0
        }
        let diagnosticObject: [String: Any] = [
            "clusterCount": clusterCount, "modelSpeakerSlots": segmentation.numSpeakers,
            "frameDuration": frameDuration, "sourceBound": maxTime,
            "preClampExpectedCounts": diagnosticCounts,
            "postClampCounts": speakerCountPerFrame
        ]
        if let diagnosticData = try? JSONSerialization.data(withJSONObject: diagnosticObject, options: [.sortedKeys]),
            let diagnosticText = String(data: diagnosticData, encoding: .utf8) {
            print("VOICEMATRIX_PRECLAMP_DIAGNOSTIC " + diagnosticText)
        }

'''
after=before.replace(needle,addition+needle);dst.write_text(after)
changed=[]
for p in original.rglob('*'):
 if p.is_file():
  rel=p.relative_to(original)
  if p.read_bytes()!=(copy/rel).read_bytes():changed.append(str(rel))
assert changed==[relative]
root.joinpath('overlap-evidence/instrumentation.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile=relative,tofile='diagnostic-copy/'+relative)))
root.joinpath('overlap-evidence/instrumentation.json').write_text(json.dumps({'scope':'Copied vendor, observation only; no product change','onlyChangedFile':relative,'originalSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'instrumentedSHA256':hashlib.sha256(dst.read_bytes()).hexdigest()},indent=2))
p=root/'probes/overlap-stress/Package.swift';s=p.read_text();assert s.count('../../Vendors/FluidAudio')==1;p.write_text(s.replace('../../Vendors/FluidAudio','../../diagnostic-vendor/FluidAudio'))
