# Reference-transcribed speech and matching retrieval

## Outcome
The matching VCTK p226 index executes in an isolated CPU adapter and raises uncalibrated target-speaker cosine scores, but worsens automated reference-transcript WER on one of two preselected utterances. This does not justify enabling it in the app. The candidate's production retrieval guard remains unchanged; no production limits or quality thresholds were relaxed.

| LibriSpeech utterance | Retrieval | ASR edits / reference words | Target cosine |
|---|---:|---:|---:|
| 6930-75918-0000 | 0 | 0 / 8 | 0.7409 |
| 6930-75918-0000 | 0.375 | 0 / 8 | 0.7765 |
| 6930-75918-0000 | 0.75 | 0 / 8 | 0.9532 |
| 8455-210777-0028 | 0 | 0 / 17 | 0.7609 |
| 8455-210777-0028 | 0.375 | 3 / 17 | 0.7890 |
| 8455-210777-0028 | 0.75 | 3 / 17 | 0.8378 |

The longer utterance's retrieval outputs were recognized as "a mist that" in place of "amidst the". Both nonzero rates had 17.65% automated WER on that utterance, versus 0% with retrieval off. Aggregate converted WER across just 25 reference words is 0/25 without retrieval and 3/25 (12%) with either nonzero rate. The prepared input itself had 2/17 errors on the longer utterance, so ASR input/output disagreement alone would have penalized a correctly recognized conversion. Published references resolve that scoring ambiguity; they do not turn automated ASR into human listening.

## Controlled experiment and provenance
Selected test-clean rows 0 and 1000 before conversion/scoring from openslr/librispeech_asr revision 71cacbfb7e2354c4226d01e70d77d5fca3d04ba1. Two distinct speakers; full utterances of 3.505 and 7.735 seconds, no trimming. LibriSpeech is CC BY 4.0: https://www.openslr.org/12. Attribution: Vassil Panayotov, Guoguo Chen, Daniel Povey and Sanjeev Khudanpur, "LibriSpeech: An ASR corpus based on public domain audio books", ICASSP 2015. Original files, native prepared samples, pitch arrays, reference transcripts, revision and hashes are retained. Signed asset query strings are not stored.

Used the existing exact VCTK p226 model, native default pitch, HuBERT encoder, fixed random inputs, and preselected retrieval rates 0, 0.375 and 0.75. Same pinned Whisper tiny.en and WavLM models as prior evaluation, loaded offline. Decoder sequence lengths were 9–20, below the 128-new-token limit. WER uses lowercase word tokens, preserving apostrophes. The JSON field normalizedDisagreement under asrWERAgainstPublishedReference is the reference-normalized word edit rate.

Index: Nekochu/RVC-VCTK_Voice-sample revision 005c2f948ee9dafd7e3aa7f261b4c3a24beebeef, M/p226/added_IVF1161_Flat_nprobe_1_Mp226_v2.index. SHA-256 7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50; 143140059 bytes; 45313 x 768 vectors, IVF Flat nprobe=1. Original index and model were not modified. Model publisher declares Apache-2.0; existing model/dataset license and attribution files remain preserved.

## Implementation and verification
Added a separate evaluation-only adapter accepting exactly this hash and vector count under a 160 MiB file ceiling. It retains eight-neighbor search, nprobe=1 and the existing bounded exact fallback for missing neighbors. It does not alter production's 128 MiB / 20000-vector caps or admit the old diagnostic index for the candidate.

Six actual WAV outputs and all nine synthesis chunks passed the unchanged ONNX/PyTorch limits (max absolute error <= 2e-4, RMS <= 2e-5). Worst chunk absolute error: 0.00003560632467. Complete output lengths were 140200 and 309400 samples at 40 kHz. Independent weighted reconstruction passed, including the longer input's overlap and tail; clipping was rejected. These checks establish numerical execution and reconstruction, not perceptual quality.

Conversion ran sequentially in the already approved isolated GeForce CPU runtime. No new dependency installation was needed for this experiment. Preparation used Linux native Swift code; no Mac runner was used. All new Python scripts syntax-checked. Existing production code/defaults were not changed.

## Reproduction and remaining blockers
Scripts under probes/rvc-candidates preserve pinned acquisition, preparation, bounded unpacking, conversion and scoring. prepare_librispeech_reference.py takes the pinned CPU source root, compiled RVCPitchModeChecks binary and a new output directory. The conversion/evaluation scripts run from the established isolated runtime with deps-long, source-long, cached evaluation models and candidate-vctk-p226. Binary fixture transfer was hash-bound; scripts refuse existing output directories. Evidence is in docs/qa/librispeech-retrieval.

The current phone loader cannot admit this full index: it exceeds both byte and vector limits. Supporting it needs a measured memory/storage design, not a cap increase based on desktop success. Its intelligibility regression also needs broader reference-transcribed testing before any default change. Two short utterances are a regression set after this experiment, not broad qualification.

Target anchors are three publisher reference excerpts and may overlap training data. Cosine scores have no calibrated identity threshold. Intended character voices, human listening, physical-iPhone speed/memory and post-build-5 Apple compilation remain unverified. This experiment provides no new IPA, model release, Strata update or 1.0.0 claim.
