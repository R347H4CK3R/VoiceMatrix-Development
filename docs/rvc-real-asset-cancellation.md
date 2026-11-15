# Real-asset cancellation and integrity checks

Two deterministic real-data tests exposed the same admission bug: cancelling immediately after SHA-256 finalization returned a successful snapshot despite the task being cancelled. Cancelling during copying already worked.

The production loaders now check cancellation after digest validation and again after file synchronization, before admitting the verified snapshot. Existing error cleanup removes partial/private files. Hash allowlists, size limits, voice assets and success-path formats are unchanged.

## Real data and before/after results

| Asset | Size | During-copy cancellation | Post-digest before fix | Post-digest after fix |
| --- | ---: | --- | --- | --- |
| VCTK p226 vector bank | 139,201,536 bytes | Rejected after 3 blocks | Returned bank | Rejected after 2,833 blocks |
| HuBERT ONNX model | 377,647,665 bytes | Rejected after 3 blocks | Returned snapshot | Rejected after 361 blocks |

All corrected cases threw CancellationError and left the dedicated cache empty. Vector-bank descriptor counts returned to their starting value. Both original asset hashes were checked before and after and remained unchanged. The test cancellation is deterministic: it cancels the actual Swift task from the update/final-digest callbacks. Streaming SHA-256 is computed by /usr/bin/sha256sum, not a fabricated expected digest.

The failing HuBERT case initially left an accepted snapshot in its private cache; the test explicitly removed that test-owned snapshot after recording the failure. The failing vector-bank case returned an open private bank but did not leak its descriptor after release. Neither test modified the original model or vector asset.

## Integrity rejection

A separate disposable copy of HuBERT had one bit flipped at byte offset 4096, retaining the original manifest and exact file size. The production snapshot loader rejected it as invalidAsset, left the cache empty, and never invoked inference. Original SHA-256 remained 980f264a909ff3d85d513e924304b1c179ff5d17280dda0b011ec01cb366aa68; the corrupted copy hash was a349886f048052a6b8bee55df15454965807f35f53e1767df4db740d0a72d5a9.

The actual vector-bank hash remained 2326a4ca21cedbea61532a5c5b9fcba752f6de2ba9ff9cee5ecb8abda3a6bb98. Original voices and previous evidence were preserved.

## Regression coverage and reproduction

Four portable test methods passed across test_rvc_native_synthesis, test_rvc_disk_vectors, test_rvc_retrieval_pack and test_rvc_model_admission. Lightweight tests now exercise the post-digest cancellation boundary without requiring large assets. Those unit tests use controlled digest callbacks; the separate real-asset tests above supply actual SHA-256.

Real-data harnesses are tests/native/RVCRealCancellationChecks.swift and tests/native/RVCModelCancellationChecks.swift. Compile with Swift 6.1.3 and the respective production sources:
- Vector harness: RVCDiskVectorBank.swift. Arguments: vector-file, dedicated-cache-directory, 45313, expected SHA-256.
- Model harness: RVCSynthesisInputs.swift and RVCSynthesisAssets.swift. Arguments: pinned model-pack directory and dedicated-cache-directory. Add reject for a disposable tampered model pack.

Use an empty dedicated cache. The model harness removes only a returned test snapshot when recording a failure; it does not edit input models. The corruption setup must operate on a copy, never the original asset.

Before/after evidence is preserved under docs/qa/real-asset-cancellation. No model or audio binary was committed. These are real Linux Swift/Foundation storage tests, not Apple ORT construction or physical-device tests. A synchronous load already in progress still cannot be preempted; the checks prevent success at the tested final-admission boundaries.

No new voice-quality result, human listening qualification, iPhone verification, build, source-feed change or preview publication is claimed.
