# Standalone pipeline verification — 2026-11-15

The real production coordinator completed the audio-only and video cases in Apple run 43679329419, commit 457128e8592b40f1d71484fef8abaabb9574bb55. Both executions denied network access. The diagnostic target had omitted LocalReferenceAttempt and LocalVoiceProfilePackage; adding these source dependencies fixed compilation. No production acceptance threshold was relaxed.

Both cases retained the original source hash through cancellation/resume, preserved a prior profile, imported a new reference, reloaded its identity and bytes from a fresh store, and generated a new sentence through the reloaded library. The new sentence had automated word error rate 0. The video case additionally retained a frame and recognized its original DEMO label. Character identity was not inferred.

Both containers use the same installed macOS synthetic neutral speech, not independent human holdouts. They produced identical new-speech bytes (SHA-256 da2c1b3ab751383f624b1d33d4469e0cbc14fb493bdfdb137ec093c0b4ecd2a6), 2.4 seconds of mono 24 kHz PCM. Reference/preview embedding cosine was 0.7813496344068545; this is not a likeness acceptance metric. The first candidate was conservatively rejected for music/singing risk; the bounded fallback succeeded without weakening screening.

Downloaded evidence archives were checksum verified; JSON reports are retained under qa/native-standalone-20261115. Generated WAVs remain preserved in the workflow artifacts and workspace. Dependency resolution was independent, recorded by SHA-256; this is not a re-execution of the published IPA.

Build 7 remains the published unsigned preview. Later changes here repair test configuration and assertions; no new app release was made. Physical-iPhone behavior, human listening, overlapping voices, music separation and broad real-speech voice quality remain unverified or incomplete.

The build-7 simulator run's visible UI tests passed, but the whole suite failed at a legacy-policy assertion expecting version 2 rather than the implemented version 3. That assertion and explicit legacy crop generation were corrected; the full simulator suite has not been rerun. A focused production CoreML probe verifies migration and tamper rejection separately.

Focused CoreML run 43679691835 (commit c62519a3be61a9c3e66827f214fc9bb111d486ae) PASSED. It exercised actual adapter migration for nil/1/2 policy records, verified both exact primary/fallback crop coordinates, rejected tampered legacy crops, and then recovered the two separate source speakers from the pinned real A-B-A speech fixture. The preceding new probe failed because its test incorrectly expected one crop instead of the policy's primary plus fallback; that expectation was corrected using compiled portable policy output. No production behavior or thresholds changed for this repair.
