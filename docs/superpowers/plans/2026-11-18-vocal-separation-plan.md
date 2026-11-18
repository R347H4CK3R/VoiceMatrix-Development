# Bounded Vocal Separation Implementation Plan

> For agentic workers: use subagent-driven-development with independent review before publication.

**Goal:** Real on-device vocals/accompaniment output for an entire local clip up to10seconds.
**Architecture:** Hash-pinned Spleeter ONNX models, pure native spectral preprocessing/reconstruction, explicit import/run UI and atomic paired result storage. Existing preview source and release refs remain frozen.
**Tech Stack:** Swift, existing ONNX Runtime1.24.2 CPU, AVFoundation, Foundation FFT; Python/NumPy/ORT reference tests.
**Spec:** docs/superpowers/specs/2026-11-18-vocal-separation-design.md

## Global constraints
44100Hz stereo; maximum441000frames; maximum64MiB input. Exact model hashes and spectral parameters are in the spec. No silent trim, no automatic identity/training claim, no network inference. Preserve original and all completed outputs. Cancellation retains processing ownership until synchronous inference returns.

## Review focus
- Boundary impulses and partial hop must retain exact original frame count.
- Native prediction tensors must match validated Python preprocessing ordering.
- A failed second stem write cannot expose first stem as complete pair.
- Background cancellation cannot release processing lease while inference still runs.
- Models absent, replaced or corrupted must fail before inference and preserve prior work.

## Tasks
- [ ] Core: add VocalSeparationDSP.prepare(left:right:) and reconstruct(prepared:vocals:accompaniment:) with actual FFT/iFFT; first observe failing test, then NumPy/native parity for silence, impulse, unequal channels and partial finalhop.
- [ ] Models: prepare_vocal_separation.py pins archive+eachONNX; VocalSeparationAssets validates immutable snapshots. Test changed bytes, missing files, oversized inputs and no overwrite.
- [ ] Inference: VocalSeparationEngine(actor) owns CPU sessions and runs exact[2,1,512,1024] x/y graphs. Real pinned model native/reference parity must pass; mocks alone insufficient.
- [ ] User workflow: SeparationStore plus bounded stereo AVFoundation import and explicit Separate UI. Both stems use shared gain only if needed, recorded explicitly. Test actualfilesystem interruptions and originalhash preservation.
- [ ] Integration: bundled Separation folder and dedicated native parity gate; full appcompile and currentUI gates after review. Never claim physicaldevice performance or perceptualquality from graph parity.
- [ ] Independent review and corrections, exactcommit CI, then packaging only when authorized and verified.
