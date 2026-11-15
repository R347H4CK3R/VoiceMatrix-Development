# Native reference duration admission

LocalVideoAudio.extract now checks decoded 24 kHz PCM frame count against the requested duration before signal scoring and WAV creation. LocalStudioEvidence.referenceCoversInterval admits only 0.5–15 second references, 12,000–360,000 frames, and a maximum absolute difference of 1,200 frames (50 ms). NaN/infinite requests and incomplete/oversized decoded intervals are rejected. Source handling and existing voices are unchanged.

Portable Swift regression cases cover exact duration, codec rounding, the 50 ms boundary and one frame outside it in either direction, minimum/maximum references, invalid frame counts and nonfinite durations. The extraction wiring is checked separately; this source-contract check is not media-runtime execution.

The legacy candidate mismatch was traced through its actual workflow: project.yml builds 0.4.9 build 5, but both character_package inspect and verify_character_kit required build 3. Both workflow consumers now require build 5. Project version/build and publication configuration were not changed. The source regression requires agreement among project and both workflow checks. This corrects a genuine inspection failure; it does not prove that a fresh IPA compiles or runs.

Verification on 2026-11-15: 21 affected tests passed across local-video-studio, verbose-candidate, diagnostic-trigger and direct-profile modules. The expanded duration-boundary harness then passed again. Swift frontend parsing of LocalVideoAudio.swift and LocalStudioEvidence.swift passed. The previous full 765-test run is recorded in reference-extraction-coverage.md; both failures from that run now pass in targeted reruns. No fresh full-suite result is claimed.

AVFoundation execution, Apple SDK compilation, physical iPhone behavior, neural diarization and listening checks remain unrun. No Mac job was launched; the development commit uses [skip ci]. GeForce and published artifacts were untouched.

Follow-up: extraction now also rejects nonfinite, offset or discontinuous sample-buffer timestamps more than 50 ms from the selected source start plus already-decoded frame count. This prevents merely concatenating gaps into an apparently valid reference. Portable policy tests cover aligned timestamps, small codec offsets, large offsets, nonfinite timestamps and invalid bounds. Source-wiring checks confirm admission precedes byte accumulation. The pending Mac run 43673643024 tests commit 54dfaeff and does not include this later timeline guard; no Mac validation of this guard is claimed.
