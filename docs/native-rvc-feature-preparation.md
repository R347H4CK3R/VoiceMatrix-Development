# Native RVC pitch and feature preparation

Implemented in VoiceMatrix/RVCFeaturePreparation.swift. This is real Foundation Swift used by the application source target, with no model/runtime dependency. The offline RVC UI remains disabled because the surrounding inference pipeline is not complete.

## Implemented boundary

Pitch input is an extracted nonnegative frequency contour, not raw audio. The stage performs upstream zero-gap interpolation with constant endpoint extension, semitone shifting, mel mapping, clipping and ties-to-even coarse-bin quantization. Completely unvoiced input remains zero Hz / bin 1. The 3,000-frame bound includes any caller-provided context; semitone changes are bounded to -24...24.

Feature input is row-major float32 v2 encoder output (768 dimensions), eight already-selected neighbor vectors and their positive squared-L2 distances, plus aligned continuous pitch. The stage implements squared reciprocal-distance weighting, normalized retrieval blending, nearest-neighbor frame doubling and upstream protection for pitch values below 1 Hz. Retrieval can be disabled without an index. Output provides the frame count and row-major features for the synthesizer adapter.

The API supports at most 1,500 encoder rows (3,000 output frames), including context. It validates shapes before multiplication/allocation; rejects nonfinite, degenerate or overflowing values; and checks cancellation at entry, each row and before returning. Callers should execute this CPU work off the main actor. Supplied tensors are read-only and no file/network operations occur.

## Provenance and licensing

Algorithm source: RVC-Project/Retrieval-based-Voice-Conversion-WebUI, commit 81eed5e8f68b6bed1789f682fe78cdd324495afc, infer/vc/pipeline.py, get_f0 and vc methods; Git blob 2aa3235d5464018b5017f60898264c4dd1b8bab8. This is a translation of non-neural processing, not redistributed model weights.

The upstream MIT copyright/permission notice is preserved in LICENSES/RVC-MIT.txt and explicitly included as an app resource in project.yml. Existing model, reference, resource and license files remain unchanged.

## Validation

Tests compile the production Swift source into a Linux executable. Six behavioral tests cover literal pitch contours, independent NumPy equations, deterministic random 1/3/149-row tensors, hand-calculated neighbor/protection values, no-index operation, malformed/oversized shapes, degenerate weights and cancellation. Missing implementation failed initially; the missing no-index behavior was then reproduced before its fix.

The Foundation gate includes these six tests and passed 12 tests with no skips. The existing packaging suite passed 22 tests. All 59 app Swift files passed syntax parsing; this is not Apple SDK typechecking. A mistyped nonexistent dependency-test module initially failed to import; the corrected existing packaging suite passed.

## Remaining integration and honest limits

This stage consumes pitch, encoder and retrieval results. It does not extract pitch from audio, run HuBERT, search a model index, synthesize a waveform, train RVC or separate music. It does not convert an F5 voice into an RVC model. Next, bind these arrays to real hash-verified intermediate captures and implement the encoder/index/synthesizer adapters and audio preprocessing/postprocessing.

No actual neural tensors or model weights were available in this checkout. Numerical tests use synthetic inputs; they are not full-pipeline neural parity, audio quality, identity, phone performance or release evidence. No Mac jobs, paid services, new model downloads or publications were performed.

Full Linux discovery: 752 tests, 748 passed, four platform skips, zero failures/errors (259.946 seconds). Skips remain the three Windows-specific cases and the Apple CryptoKit contract. The MIT resource configuration received the separate 22-test packaging pass after it was added.
