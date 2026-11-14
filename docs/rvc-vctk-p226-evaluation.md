# VCTK p226 evaluation candidate

## Provenance and compatibility
Nekochu/RVC-VCTK_Voice-sample revision 005c2f948ee9dafd7e3aa7f261b4c3a24beebeef, M/p226/Mp226.pth, SHA-256 3c4c2e8ea977d7c08793126aace4baa47028b4c1bf7cd46ae5a9c359b0216693. The publisher declares Apache-2.0 and VCTK training data. The original University of Edinburgh corpus license was checked as CC BY 4.0. Model card, attribution and full license texts are retained in docs/qa/vctk-p226 and included as app resources.

Checkpoint metadata: v2, pitch-aware, 40 kHz, 250 epochs. Loaded with PyTorch 2.6 weights_only=True. Exported using the existing pinned RVC source, explicit noise and fixed 922-frame profile. Phase accumulation was promoted to float64. Result SHA-256: f7519d6f3c248f6eb2acabd11352e0abf91515a7e95662fdb23a5b1f1e009dcc.

## Actual output checks
Two previously used CC0 human-speech regression fixtures, 468c and 4b13, were each converted to a complete 10-second 40 kHz PCM16 file. All four chunks passed unchanged ONNX/PyTorch gates (max absolute error <= 2e-4, RMS <= 2e-5). Worst observed chunk max absolute error: 0.0001374781; worst RMS: 0.00000092253. No fresh-heldout claim: earlier scripts used the word Fresh for these fixtures; that describes their initial acquisition, not this evaluation.

With retrieval disabled for both old and candidate models and native pitch unchanged:

| Fixture | Old transcript edits | Candidate edits | Old target cosine | Candidate target cosine |
|---|---:|---:|---:|---:|
| 468c | 6 | 5 | 0.7550 | 0.8525 |
| 4b13 | 7 | 8 | 0.7470 | 0.7934 |

Edits compare automated input/output transcripts, not ground-truth WER. Speaker cosines use three 10-second excerpts at 0, 20 and 40 seconds of the publisher's p226.flac; those excerpts may be training data. These scores are uncalibrated and do not establish identity. One intelligibility proxy improved and one regressed. The candidate is **not production-qualified**.

## Integration
The native asset allowlist admits only this exact exported digest in addition to the existing diagnostic graph. The original diagnostic model remains supported; the existing voice library is untouched. The UI names the selected evaluation model. A guard rejects the old synthetic voice's retrieval index for the candidate; retrieval is explicitly disabled and logged when this model is selected. Arbitrary model hashes remain rejected.

32 existing control/feature/package tests and native candidate plus legacy asset checks pass (34 unittest cases in the final run). Swift syntax passes. The new UI/adapter changes have not been Apple-SDK compiled or run on an iPhone. The published build 5 intentionally does not accept this new model. No IPA or model release was published.

A private, CRC-checked evaluation pack was prepared on the existing development device. It includes the exported model, manifest, provenance, licenses and modification notice. The source model, audio references and all existing voice assets were retained.

## Remaining gaps
Human listening, fresh independent speech coverage, physical-iPhone speed/memory and sustained conversion tests remain unrun. A licensed corpus candidate does not supply the user's intended character voices. Production-quality qualification and compatible voice-specific retrieval need additional work; these results do not justify 1.0.0.

Follow-up: see rvc-vctk-heldout-pitch.md for two newly selected speech fixtures, controlled pitch comparisons and the opt-in precision-refinement integration. The default remains unchanged and the model remains evaluation-only.
