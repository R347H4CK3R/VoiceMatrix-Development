# Native numerical baseline remains failed

Exact native run44506580113 at commit12cb5be24748ee53c77f80898c5006d379c7778c installed verified19wheel closure, loaded pinned NeMo2.3.1 selected methods/original stored buffers, traced and converted CoreML, exercised21 owned cases. Shapes, lengths, dtypes, finite values and padded-frame zero checks succeeded. Original numerical gates failed9cases. No accepted model artifact was emitted.

Diagnostic artifact14519622214 SHA2560ca1589c2791a0a6ac789b234ceb3de4077f4c13f8d04f70014c5e62bf44aa68 is independently downloaded and verified. original-native-baseline.json is the report extracted from it, unmodified except JSON whitespace. Old thresholds max1e-3/RMS1e-4 remain unchanged.

Portable NumPy FP32 source-order normalization reproduces the original Torch constant-logmel offsets0.275753/0.276108 for101/1501frames. Subtracting first-valid-frame before statistics gives zero for constant rows and less than9e-8 vs FP64 across nine constructed low-variance probes. These are portable operation-order findings, not native candidate evidence. It cannot simultaneously output mathematicalzero and match originalTorch−0.276 within0.001. Preserve old baseline failure and report explicit deviations for any candidate correction.

Pinned primary-source alternative: mattt/AnySpeechRecognizer06e0842b164bdb7ddc16f365757a807980745bf8 Sources/AnySpeechRecognizer/Parakeet/ParakeetMelFrontend.swift uses Double accumulation for mean/variance to keep constant silence rowszero. Its overall frontend is NeMo≥2.5/3 and MUST NOT silently substitute for the original2.3.1 reflect padding/+1frame count/preemphasis semantics. Original exact buffers must remain provenance-bound.

Next diagnostic must separate preemphasis/power/mel/log/reduction/normalization; feed identical logmel arrays into both backend normalizers; compare same FP64 host normalization of each backend's logmel to isolate upstream differences; retain low-length/padded masking checks. No second native run authorized from this file. No production app integration or release/feed changes.
