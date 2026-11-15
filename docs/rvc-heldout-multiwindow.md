# New held-out multi-window speech evaluation

LibriSpeech test-clean rows 500 and 1500 were selected before conversion or scoring, with retrieval rates 0 and 0.125 fixed in advance. The two new speakers/utterances are 2961-960-0003 (17.315 seconds) and 4507-16021-0031 (14.310 seconds). Each requires three conversion windows. These cases are now regression fixtures, not fresh hold-outs for future tuning.

## Outcomes

All four complete conversions and all 12 window parity checks passed unchanged gates: maximum absolute error <=2e-4 and RMS <=2e-5. Observed worst values were 6.853044e-5 and 6.523179e-7. Full reconstruction matched the independent reference-weighting oracle, preserved exactly 692,600 or 572,400 output samples at 40 kHz, covered both tails, and did not clip PCM.

| Utterance | Input ASR edits | Retrieval off edits | 12.5% edits | Target cosine off | Target cosine 12.5% |
| --- | --- | --- | --- | --- | --- |
| 2961-960-0003 | 0/39 | 0/39 | 0/39 | 0.88689 | 0.88735 |
| 4507-16021-0031 | 3/34 | 3/34 | 3/34 | 0.89437 | 0.90558 |

For the second utterance, equal edit totals do not mean identical errors: the input ASR omitted a word, whereas converted ASR produced a different ending. All transcripts and scores are preserved. Decoder sequences were 37–44 tokens with a fixed 128-new-token ceiling, not cut off at that ceiling.

This batch provides no evidence of a WER regression at 12.5%, and a small increase in uncalibrated target-speaker cosine. It does not establish that retrieval improves all speech, that the audio sounds natural, or that the target identity is verified. Prior mixed results remain relevant; the candidate default stays retrieval off.

## Execution and integration scope

Linux performed the real native preprocessing and default pitch extraction. The existing authorized isolated Windows CPU runtime performed pinned HuBERT encoding, matching full-index retrieval, PyTorch reference synthesis, exported ONNX synthesis and complete overlap reconstruction. This is not execution of the phone's Swift ORT wrapper, its random generator, or a physical iPhone.

The test harness had limited prepared float input to 1 MiB despite admitting 30-second clips. The bounded snapshot ceiling was corrected to 480,000 float samples (1,920,000 bytes) so the preselected 17.315-second utterance could run. The duration limit, parity gates, model hashes and scoring configuration were not loosened. Application behavior was not changed in this step.

Source review also confirms the phone file workflow reads bounded windows, keeps an overlap reconstructor, writes converted floats to scratch storage, and emits final PCM in 16,384-sample blocks. These new three-window cases exercise the reference reconstruction path; they do not prove two-hour stability or phone memory/performance.

## Provenance and reproduction

Evidence lives in docs/qa/librispeech-heldout-next: selection.json, four conversion reports and evaluation.json. It includes exact input/PCM/window/model/index hashes, published transcripts, all ASR outputs, output WAV hashes and evaluator model provenance. New WAVs remain preserved in the isolated evaluation workspace; source control contains reports and probes, not model or audio binaries.

Source corpus: [OpenSLR LibriSpeech](https://www.openslr.org/12), CC BY 4.0, Panayotov, Chen, Povey and Khudanpur (2015). Dataset revision is 71cacbfb7e2354c4226d01e70d77d5fca3d04ba1. The existing VCTK p226 publisher/model and training-data license records are retained in evaluation.json. Model reuse is not a new legal or production-quality qualification.

The pinned Whisper and WavLM evaluators run offline. Speaker anchors use three ten-second p226 segments at offsets 0/20/40 seconds and may occur in training data; their cosine scores are uncalibrated. The transfer archive SHA-256 was 60c7a5215650a35a873e5e738d4651903b4756bf9db35f9bfd91bd9dc61b8b13, checked before extracting only six allowlisted files and validating individual hashes.

Reproduction scripts under probes/rvc-candidates are prepare_librispeech_heldout_next.py, convert_librispeech_heldout_next.py, evaluate_librispeech_heldout_next.py and run_librispeech_heldout_next.py. They retain the explicitly approved evaluation workspace layout and require the previously pinned cached assets. Conversion and scoring disable network inference, refuse existing outputs, and use assertions as gates: run Python without -O. Prior outputs must be preserved before reruns.

Physical-device verification, Apple compilation of the latest native integration, human listening and production voice qualification remain outstanding. Existing voices, licenses, evidence, defaults and published build remain unchanged. No new IPA, feed entry or model pack was published.
