# Standalone original Parakeet frontend prototype

This is an isolated Swift/Accelerate prototype. It has no VoiceMatrix product
code, Swift wrapper integration, CoreML model, full weights, or CI configuration.
Swift is not installed in the preparation environment, so the native code and
XCTest assertions have not compiled or run there. Tests were written before the
implementation; native RED/GREEN must be collected separately.

The public initializer checks exact byte count and SHA-256 of the two original
NVIDIA little-endian Float32 buffers using CryptoKit. No arrays are distributed in
this directory. Source bundle attribution for externally supplied original
buffers must travel with them (NVIDIA, CC BY 4.0):
[original pinned model](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/tree/541d1f99c6b0c3cd0b11a95167540bb8edefd82b).

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

On native macOS Apple Silicon, when reviewed and authorized:

```sh
ASR_SWIFT_FIXTURES=/path/to/generated-fixtures \
ASR_SWIFT_BUFFERS=/path/to/original-buffers swift test
swift run -c release parakeet231-frontend \
  --input input.audio.f32le --valid 240000 \
  --window /path/to/original-buffers/window.f32le \
  --filterbank /path/to/original-buffers/filterbank.f32le \
  --output actual.mel.f32le --metadata result.json
```

Inputs and output are raw little-endian Float32. Output bin 0 precedes bin 1
(each row has `frames` samples). CLI bounds input sizes and refuses overwrites.
It emits both files in a successful run; if writing the second output fails,
the first may remain, so a nonzero exit leaves no valid evidence pair.
Run the CLI on each independently generated fixture and compare with the
separate oracle tool; executable output, native tests, and hardware performance
are all currently unverified. Synthesized speech fixtures, if run later, do not
establish real-speech or full ASR word/timing acceptance.
