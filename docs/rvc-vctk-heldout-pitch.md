# VCTK held-out pitch comparison and optional integration

## Controlled experiment
Investigated the 4b13 regression without changing the pinned VCTK p226 model, retrieval (zero), input, or random tensors. Compared the original native parabolic refinement, the existing independent 32-point Hann-sinc refinement, and pinned Parselmouth reference pitch. The reference is not ground-truth pitch.

Before evaluation, selected the next two original, non-enhanced CC0 filenames after 4b13 at dataset revision 323332d33f997de8394f24a193e1a76df720e01a: 4b70 and 5b55. They were new to this development evaluation, not selected by favorable outcomes. Original audio hashes, native code hashes, and prepared-window hashes are retained. Recompiling native preparation exactly reproduced both prepared audio and pitch arrays. These clips become regression fixtures after this experiment.

Six new full-duration held-out outputs and two regression comparison outputs were generated. All 16 newly evaluated synthesis chunks passed the existing ONNX/PyTorch error limits; worst max absolute error was 0.00001918525. Every output contains all 400000 samples (10 seconds at 40 kHz). No gate was weakened.

## Results
ASR edits compare deterministic Whisper-tiny.en output transcripts with its input transcript, not human ground-truth WER. Speaker scores are WavLM cosine similarity against the same three potentially in-training target reference excerpts; there is no calibrated identity threshold.

| Fixture | Original edits | Sinc32 edits | Parselmouth edits | Original target cosine | Sinc32 target cosine |
|---|---:|---:|---:|---:|---:|
| 4b13 regression | 8 | 7 | 9 | 0.7934 | 0.7912 |
| 4b70 new | 3 | 2 | 2 | 0.8593 | 0.8605 |
| 5b55 new | 2 | 2 | 2 | 0.8323 | 0.8298 |

The original pitch already closely matched Parselmouth on voiced frames: the problematic 4b13 chunk p95 errors were 1.66 and 2.92 cents, with no joint-voiced frame over 50 cents. Sinc32 reduced those p95 errors to 0.054 and 0.068 cents. This is a precision improvement, not evidence that gross pitch tracking caused the word substitutions. Reference pitch did not fix the regression. Remaining errors require further investigation and listening; the entire quality problem is not resolved.

## Source integration
Added optional `refinePeaks`/`refinePitch` parameters and an explicitly labeled evaluation toggle. Refinement defaults off. The original calculation remains unchanged when off; reset returns to that default. The selected mode is captured once for every chunk and included in the live log. Voices, models, licenses and retrieval guards are unchanged.

A new actual-audio regression harness first failed because the option did not exist. After implementation, both integrated modes exactly matched the previously evaluated prepared audio and complete pitch arrays on both new clips, across three repeated runs each (12 exact comparisons). 34 existing portable tests and full Swift syntax parsing also passed.

Linux CPU preprocessing-plus-pitch medians for 10-second audio: original 0.716/0.718 seconds; refined 1.268/1.218 seconds (1.77x/1.70x). These are not full-inference or phone timings. Additional cost and mixed speaker-score changes are disclosed; no default change or production-quality claim is justified.

## Reproduction and limits
The probes/rvc-candidates scripts preserve selection/preparation, exact-source verification, conversion, diagnosis, and evaluation. Preparation uses the existing pinned source closure and ExportNativeAudio.swift helper from the earlier CPU evidence bundle. `verify_integrated_pitch_modes.py` takes the prepared fixture root, a binary compiled from tests/native/RVCPitchModeChecks.swift plus native preprocessing/chunk/pitch sources, and a new result path. Decoder dependencies remain isolated: soundfile 0.13.1, cffi 1.17.1, pycparser 2.22.

Human listening, intended character likeness, physical-iPhone speed/memory and Apple compilation of this change remain unrun. Only a small corpus was tested; ASR sensitivity can affect edit counts. The target reference may be training data. Model provenance and license files remain intact. No app or model release was published.
