# Python-coordinated Matroska audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Do not implement before parent reviews this draft.

**Goal:** On iPhone, produce an analysis-ready PCM source provably decoded from the genuine MKV requested by bundled Python.

**Architecture:** Python returns a typed stage decision; Swift validates capabilities and executes fixed native operations. Native receipts bind originals, MKV and PCM. A narrow writer-subset reader has no MP4 decoder input.

**Tech Stack:** Embedded CPython, Swift, existing MP4SampleTable/LocalMKVExport/MatroskaWriter and Apple AudioToolbox.

**Spec:** 2026-11-19-python-mkv-audio-design.md

## Global constraints

No runtime code, shell, arbitrary paths/calls, new media dependencies, unrelated cleanup, release, or IPA. First slice single H.264 and single AAC-LC <=720p, <=1,800s and existing disk/transfer limits. User-authorized media only. Keep existing acquisition and public feed untouched. No MP4 analysis fallback in strict mode. Use a clean worktree and preserve existing feature branch.

## Task 1: Python stage policy with private dispatch
- [ ] Add `tests/test_mkv_stage_policy.py`: fresh verified acquisition -> prepare; matching MKV -> decode; matching PCM -> complete; changed hashes / mixed attempts / invalid schema or stage -> reject. Run and observe RED.
- [ ] Create `python-resolver/voicematrix_mkv_stage.py`, `decide(request_json: str) -> str`. Input: schemaVersion, job UUID, phase, acquisitionSHA256, optional MKV and PCM receipts with their parent hashes. Output: schemaVersion, UUID and one of prepare/decode/complete/reject. No URL/path or native invocation. Persisted state authority remains Swift.
- [ ] Add fixed second operation to VMPythonRuntime.m and package inventory under tools/python-runtime; operation determines a hard-coded entry point, never accepts module/function name from JSON. Existing resolver unchanged. Native bridge uses bounded JSON, timeout, cancellation, request identity; Swift async media tasks run after Python callback returns.
- [ ] Verify GREEN with policy and package tests, native cancellation/no-op-on-stale-callback test, then freeze/review.

## Task 2: Reader from actual writer bytes
- [ ] Add `VoiceMatrixTests/LocalMatroskaAudioReaderTests.swift` with `testReadsAACFromMKVWithoutPublishedCompanion`, `testRejectsLacingAndOverflow`, `testRejectsChangedDescriptorAndMalformedPadding`. Build macOS/iOS-native fixture using existing LocalMKVExport and independently captured expected AAC payload SHA sequence.
- [ ] Create `VoiceMatrix/LocalMatroskaAudioReader.swift`: stream using bounded, no-follow descriptor. Proposed interface `init(url: URL, expectedSHA256: String) throws`, immutable AAC format fields, `nextAAC() throws -> Packet?`, `verifyUnchanged() throws`. Packet carries PTS milliseconds, duration milliseconds, discard nanoseconds and owned payload. No MP4 URL available. Check writer-layout and arithmetic bounds before allocating or seeking.
- [ ] GREEN includes mutating a specific AAC payload and verifying rejection, invalid audio track count/ID, repeated / unknown-sized child, and EOF exactness. Hex fixtures only for malformed container tests; never use fabricated payloads for audio correctness claim.

## Task 3: Independent AAC timing/decode verification
- [ ] Add `VoiceMatrixTests/LocalMatroskaPCMTests.swift`: `testLicensedSpeechHasExactVerifiedFrameCountAndPCMParity`, `testInitialOffsetAndTrailingDiscardAreNotRetimed`, `testCancelledDecodeDoesNotCommit`. Include alternate sample rate supported by writer and last audible marker so silent padding cannot pass.
- [ ] Implement `VoiceMatrix/LocalMatroskaPCM.swift`, proposed interface `decode(reader: LocalMatroskaAudioReader, destination: URL) async throws -> PCMReceipt`. Use Apple native AAC decode with codec-private config, bounded input queues, monotonic frame clock and EOF drain. Verify timing and final discard once; fail with typed unsupported when unable to represent an edit exactly. Commit canonical WAV and receipt only after verified read completion. Report actual frame count, source payload/PCM hashes and algorithm versions.
- [ ] GREEN with independent ffmpeg oracle on runner (test-only), using frame/time parity and predeclared numeric tolerance. Structural unsupported cases never publish PCM. Independent oracle unavailable is not a pass.

## Task 4: Integrate strict source path and prove selection
- [ ] Add `VoiceMatrixTests/LocalMatroskaWorkflowTests.swift` for cancelled/restarted typed progression, consent and preserved existing files. Set correct source in native job evidence and deliberately give the MP4 companion different audio in a fixture: assert diarizer/reference receives only hash-bound MKV WAV. Changed/corrupt MKV must fail despite readable companion.
- [ ] Add `VoiceMatrix/LocalMatroskaWorkflow.swift` coordinating policy -> prepare -> verify -> decode, and opt-in strict route from LocalMediaAcquisition/LocalVideoStudio. Keep original/preview/OCR source identity separate from analysis WAV identity. Strict route returns typed unsupported if source fails; leave original mode explicit/unmodified. Do not publish incomplete evidence on restart.
- [ ] GREEN: full native workflow on source commit and unchanged legacy regressions. Prove actual MKV descriptor/input SHA and WAV actual usage in audit, not merely existence of shareable MKV. Record remaining exact10s, identity confirmation, fresh F5 generation/export and physical live URL gates as separate follow-on scope.
