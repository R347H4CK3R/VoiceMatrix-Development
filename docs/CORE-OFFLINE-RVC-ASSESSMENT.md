# Core standalone RVC assessment — 2026-11-14

Scope: assess the missing on-device RVC recording-to-voice path without launching Mac jobs. This is not a completed feature, new model, or IPA.

## Existing working routes versus missing RVC route

The app's selected-reference text generation uses F5ReferenceEngine. Its existing CharacterVoiceConversion calls OfflineVoiceConverter (the separate shared conversion engine). Neither is a trained RVC runtime. RVCOnlineStudio/Connection/Session explicitly submit to a laptop service.

project.yml declares FluidAudio and SpeechSwift/F5TTS packages and bundles Phonon, OpenVoice, ParakeetASR, Diarization and F5TTS. It does not declare a mobile RVC runtime or RVC model bundle. The tracked candidate tree contains zero .onnx, .pth or .index files. Historical reports contain model hashes and results, not the corresponding runtime assets.

## Concrete missing execution chain

tools/rvc_portable.py exports only a fixed-shape v2/f0/40k synthesizer: 100 frames, 768-dimensional input, explicit pitch, speaker and random tensors. Its capabilities explicitly exclude HuBERT, pitch extraction, retrieval, audio DSP, end-to-end conversion, dynamic shapes, CoreML and native iPhone execution.

tools/rvc_intermediate_fixture.py documents the actual one-second reference path: one second of reflected context on each side, roughly 298 synthesizer frames, and about 39,200 trimmed output samples. The existing 100-frame synthesizer evidence cannot validate this longer path. Padding or relabeling it would not complete the algorithm.

Required work before a usable local RVC feature:
1. Recover the hash-bound authorized model/index and real intermediate captures from the prior synthetic conversion experiment. Historical evidence is docs/qa/rvc-corrected-synthetic-smoke.json; it is not a new test result.
2. Export and execute the encoder and correctly shaped synthesizer using the same pinned source, model weights and explicit noise. Compare against actual intermediate tensors.
3. Implement and compare pitch extraction, retrieval and preprocessing/postprocessing, including context and output trimming. A standalone numerical helper without these connections is not an app feature.
4. Integrate the mobile model runtime, private model registry, audio ownership, bounded chunking, cancellation and output controls. Keep F5 packs separate and unchanged.
5. Produce a fresh iOS build and evaluate actual device output. Linux tests cannot establish phone memory/latency or character likeness.

Music separation is a separate missing model/runtime integration. Current local sound screening rejects unsuitable references; it is not separation.

## Verification performed

Command:
python -m unittest tests.test_rvc_portable tests.test_rvc_intermediate_fixture tests.test_rvc_validation -v

Result: 41 tests passed, zero skips, zero failures/errors (0.595 seconds). These execute admission, orchestration, tensor integrity/shape and evidence-binding checks with explicit synthetic boundaries. They do not perform real neural conversion. The Linux interpreter has NumPy and SciPy, but no Torch or ONNX Runtime installed in this environment. Installing packages alone would not supply the missing bound assets or mobile adapters.

No Mac CI, billing changes, new model downloads, release publication or voice-asset edits were made for this assessment. The unconnected RVC helper spike was stopped and its two uncommitted tests removed; no partial feature was shipped.
