# Experimental original NeMo frontend adapter

Not released or integrated into the existing app candidate. The isolated base is
4ed344a8bb859e841c35041f3f07b9510a930492. Native standalone frontend evidence
602a31f89efbddfde890dd28149235f897b04563 / run 44511546470 passed five XCTest
cases and 39 fixture comparisons to independent high-precision math. This does
not establish complete ASR acceptance, historical Torch bit parity, or iPhone performance.

The source copied into the vendor fork changes only its immutable frontend
struct to explicitly conform to Sendable. The adapter uses exact 240000-sample
physical buffers and preserves existing logical-length policy.

## Compatibility

The legacy initializer and default CoreML loader remain. The vendor-fork public
`AsrModels.preprocessor` getter is now optional: native mode has no CoreML
preprocessor. This is a source-level API compatibility change for external users,
not a claim of drop-in upstream library compatibility. No tracked call site
requires a nonoptional getter. Native compilation remains a required gate.

## Attribution and numerical scope

Semantics are taken from the Apache-licensed
[NeMo 2.3.1 features source at abddc854](https://github.com/NVIDIA-NeMo/Speech/blob/abddc854389e9efcaf38c605ef66af675fc5f8f7/nemo/collections/asr/parts/preprocessing/features.py)
(NVIDIA, Ryan Leary, and upstream authors). The shape and separation into vDSP
FFT, mel projection, and normalization were informed by the Apache-licensed
[mattt/AnySpeechRecognizer frontend fixed at 06e0842](https://github.com/mattt/AnySpeechRecognizer/blob/06e0842b164bdb7ddc16f365757a807980745bf8/Sources/AnySpeechRecognizer/Parakeet/ParakeetMelFrontend.swift)
(mattt and contributors). This is a standalone implementation of the older
math, not a copy of the newer NeMo 3 frontend with different sample-padding and
length semantics. Apache 2.0 license is included. Original third-party notices
in the source model / buffer package apply separately.

- 16 kHz mono Float32 inputs; physical span is 257...240,000 samples and
  valid samples must be 160...physical count. No padding adapter is provided.
- Global preemphasis including tail, centered reflect padding, 400-value
  window, 512-point unscaled signed-complex DFT, bins 0...256, Double power
  and mel projection, natural log with 2^-24 guard, and sample variance
  normalized with additive 1e-5.
- Logical frame count is floor(physical/160)+1. Valid count is
  floor(valid/160)+1. Frames that cannot affect the result are not
  computed; their bins are returned as positive Float32 zero.
- All arithmetic after reading the Float32 audio/window/filterbank is Double.
  Offset-anchored mean is transfer-invariant in real arithmetic and avoids
  constant-lane cancellation; this is not bit parity with historical FP32
  reductions, nor complete model or device acceptance.
- The oldest CoreML float32 gate remains separate. This prototype does not
  lower its threshold or claim compatibility with that gate.
