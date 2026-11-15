# Standalone pipeline verification — 2026-11-15

The real production coordinator completed the audio-only and video cases in Apple run 43679329419, commit 457128e8592b40f1d71484fef8abaabb9574bb55. Both executions denied network access. The diagnostic target had omitted LocalReferenceAttempt and LocalVoiceProfilePackage; adding these source dependencies fixed compilation. No production acceptance threshold was relaxed.

Both cases retained the original source hash through cancellation/resume, preserved a prior profile, imported a new reference, reloaded its identity and bytes from a fresh store, and generated a new sentence through the reloaded library. The new sentence had automated word error rate 0. The video case additionally retained a frame and recognized its original DEMO label. Character identity was not inferred.

Both containers use the same installed macOS synthetic neutral speech, not independent human holdouts. They produced identical new-speech bytes (SHA-256 da2c1b3ab751383f624b1d33d4469e0cbc14fb493bdfdb137ec093c0b4ecd2a6), 2.4 seconds of mono 24 kHz PCM. Reference/preview embedding cosine was 0.7813496344068545; this is not a likeness acceptance metric. The first candidate was conservatively rejected for music/singing risk; the bounded fallback succeeded without weakening screening.

Downloaded evidence archives were checksum verified; JSON reports are retained under qa/native-standalone-20261115. Generated WAVs remain preserved in the workflow artifacts and workspace. Dependency resolution was independent, recorded by SHA-256; this is not a re-execution of the published IPA.

Build 7 remains the published unsigned preview. Later changes here repair test configuration and assertions; no new app release was made. Physical-iPhone behavior, human listening, overlapping voices, music separation and broad real-speech voice quality remain unverified or incomplete.

The build-7 simulator run's visible UI tests passed, but the whole suite failed at a legacy-policy assertion expecting version 2 rather than the implemented version 3. That assertion and explicit legacy crop generation were corrected; the full simulator suite has not been rerun. A focused production CoreML probe verifies migration and tamper rejection separately.

Focused CoreML run 43679691835 (commit c62519a3be61a9c3e66827f214fc9bb111d486ae) PASSED. It exercised actual adapter migration for nil/1/2 policy records, verified both exact primary/fallback crop coordinates, rejected tampered legacy crops, and then recovered the two separate source speakers from the pinned real A-B-A speech fixture. The preceding new probe failed because its test incorrectly expected one crop instead of the policy's primary plus fallback; that expectation was corrected using compiled portable policy output. No production behavior or thresholds changed for this repair.

## Independent human-speech pipeline result

Run [43681000037](https://github.com/R347H4CK3R/VoiceMatrix-Development/actions/runs/43681000037), source 04fa2b993d7068bf3c304443009ea5f486b9a348, compiled the production coordinator successfully. Both pinned CC-BY 4.0 LibriSpeech recordings were recognized with automated word error rate 0 against their independent corpus transcripts. Network access was denied during execution. These recordings were previously used in component tests, so they are not fresh blind holdouts. Provenance is preserved in probes/human-local-studio/sources.json and per-case fixtures.

The complete pipeline FAILED for both recordings: one speaker was found in each, but all three candidate references per speaker were rejected by the unchanged Apple SoundAnalysis policy v1 before F5 generation. Peak music scores ranged from 0.323 to 0.398 for source 2961 and 0.213 to 0.397 for source 4507; the rejection threshold is 0.2. Some candidates also exceeded the singing threshold. These independent scores are not probabilities that sum to one. High speech scores and correct transcription do not establish absence of background music.

No human-derived profile, preview, or new generated sentence passed this run. Original sources and candidate attempts were retained. Evidence JSON is saved under qa/human-pipeline-20261115; the full checksum-verified artifact, including WAV candidates, is preserved separately. This exposes a substantive usability blocker in automatic reference screening; it must not be hidden by claiming successful recognition is successful generation.

Next required quality work is classifier/window calibration against independently labeled speech, music, singing, and mixed-audio fixtures, followed by re-running the full pipeline. No threshold was weakened to fit these two cases. Build 7 remains an unfinished preview; its production app source matched development before these diagnostic-only additions. There is no new production fix or release from this test pass, and physical-phone/listening verification remains outstanding.
