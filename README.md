# Reviewed standalone frontend preparation, native unverified

SwiftFrontend contains isolated Double/Accelerate source and XCTest. Oracle contains independent NumPy FP64 fixture generation plus exact original CC-BY4 buffers/provenance. Generated36fixture payloads are NOT committed; generate them using `python Oracle/generate.py --out <newdir>` under reviewed pinned NumPy. Optional native offline synthesized speech WAV is labeled synthetic, not real-human ASR acceptance.

Five portable fixture tests passed. Swift/clang were unavailable locally: compile, Accelerate scaling, timing and native tests remain unrun. Static independent review cleared preparation only. XCTest requires max1e-5, wholeRMS1e-6 and validRMS1e-6 against corrected mathematical reference. Old Float32 baseline failures and original1e-3/1e-4 thresholds remain in JSON, not overwritten. All11 native stage decomposition-vs-whole controls matched exactly in prior diagnostic44508586775; that diagnostic was explicitly NO_ACCEPTANCE.

No VoiceMatrix app, wrapper, package, feed or release files are present. No new CI workflow or trigger is included. Original ranges: physical257..240000, valid160..physical; invalid short domains are explicitly rejected, not silently padded. Future production adapter/fullASR, real speech/no-hallucination, device performance and cancellation gates are still mandatory.
