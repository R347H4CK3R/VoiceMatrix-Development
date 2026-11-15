# Bounded native retrieval and lower-rate evaluation

## Implemented memory change
Native retrieval previously built and sorted all candidate (ID, distance) pairs per query row and allocated a complete ID array for sparse-cluster fallback. It now retains only the best eight pairs, with identical distance-then-original-ID ordering, and iterates the fallback range directly. Candidate scratch storage is O(8), instead of O(vector count), with no candidate-bank-sized fallback ID array. Cancellation checks remain every 64 candidates.

This reduces search scratch allocation; it does not remove resident model/vector/output arrays or establish peak phone RAM. Production size, vector-count and model/index pairing guards are unchanged. Existing voice packs remain untouched.

The new test initially failed because the bounded selector was missing. After implementation, 35 targeted portable tests passed, including 20000 candidate insertions with repeated-distance ties and a real sparse-cluster search. All app Swift files passed syntax parsing. The old and new search produced exactly identical IDs, Float distances and returned vectors for 24 neighbors across three saved real feature rows; source and fixture hashes are recorded. Timing in that evidence includes fixture parsing and is not a phone or reliable speed benchmark.

## Quality experiment
The preceding experiment found 3/17 automated word errors at retrieval rates 0.375 and 0.75 on LibriSpeech 8455-210777-0028. Preselected 0.125 as the next experimental rate and row 2000 as an additional held-out input before conversion/scoring. The new input is 1580-141083-0051, speaker 1580, a complete 1.98-second, six-word utterance. It was not selected based on favorable output.

| Fixture | Retrieval | Reference-transcript edits | Target cosine |
|---|---:|---:|---:|
| 8455-210777-0028, known regression | 0 | 0/17 | 0.7609 |
| 8455-210777-0028, known regression | 0.125 | 0/17 | 0.7656 |
| 1580-141083-0051, new at selection | 0 | 0/6 | 0.8202 |
| 1580-141083-0051, new at selection | 0.125 | 0/6 | 0.8236 |

The lower rate removed the measured ASR regression in that known case while preserving recognition on the new sample. Small speaker cosine increases are descriptive, uncalibrated scores, not statistically established improvement or identity verification. These 23 reference words do not qualify a production default. Retrieval remains disabled for the candidate in the phone integration.

Three new WAV files and four synthesis chunks passed unchanged ONNX/PyTorch limits and full-duration reconstruction. Worst chunk absolute error was 0.00001774728298. The existing regression rate-zero output was reused, hash-checked against its prior report and rescored. Outputs are 79200 and 309400 samples at 40 kHz; no source trimming or clipped PCM was admitted. The CPU audio experiment uses the existing reference retrieval implementation; the native memory change was verified separately for exact neighbor equivalence.

## Provenance and reproduction
Dataset openslr/librispeech_asr revision 71cacbfb7e2354c4226d01e70d77d5fca3d04ba1, test-clean row 2000. Original FLAC SHA-256 3f7d90044d1a1ec56c95e9f0ec7a5bd1f1914259b6441148ea2991a341950b77. CC BY 4.0, attributed to Panayotov, Chen, Povey and Khudanpur, LibriSpeech (2015): https://www.openslr.org/12. Existing VCTK model/index Apache-2.0 declarations and dataset attribution remain preserved.

Pinned VCTK model, matching index, encoder, default native pitch, random inputs, offline Whisper/WavLM evaluators and comparison procedure are unchanged from rvc-librispeech-retrieval.md. Target reference anchors may be training data. Scripts are in probes/rvc-candidates; evidence and full transcripts are in docs/qa/librispeech-lowrate. prepare_librispeech_lowrate.py accepts CPU source root, native preparation binary and a new output directory. RVCRetrievalParityChecks.swift accepts the preserved real-feature JSON fixture and an output path; compile it separately with baseline and updated retrieval source to compare results.

## Remaining limitations
The matching full index is still larger than the phone loader's admitted assets. This scratch-memory improvement does not justify raising those limits. Supporting that index still requires bounded asset storage/loading and measured device memory. Broader held-out speech, human listening, intended voice likeness, physical-iPhone performance and Apple SDK compilation of these source changes remain unverified. No Mac runner, new dependency installation, app/model release or Strata update was used in this work.
