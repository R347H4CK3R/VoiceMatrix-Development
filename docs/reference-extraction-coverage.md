# Reference extraction coverage review

The companion acquisition path now checks decoded mono PCM16/24 kHz audio against the requested interval, allowing at most 50 ms codec-frame rounding. A shorter audio track in a longer video is rejected before returning a reference. Original media and extracted evidence remain retained. This is not an iPhone runtime change.

A real FFmpeg fixture (three seconds of video, one second of audio, two seconds requested) reproduced acceptance before the fix and rejection afterward. Normal extraction and prior-source preservation continue to pass.

Verification on 2026-11-15:
- Isolated official PyPI yt-dlp 2026.10.26; wheel SHA256 a05c5b5d8562f7e8a62f5334348b406af4930d56d3a65f8021d14af0e22339ae.
- 34 acquisition/preparation tests passed, including the previously skipped real format-selector test.
- Broader unittest discovery: 765 tests, 759 passed, two failures, four skips in 276.706 seconds. Temporary files used the workspace because /tmp lacked the retained-source reserve.
- The stale exact branch-exclusion expectation was corrected to cover both existing packaging exclusions and the candidate branch, retaining tests for similarly named branches. All five tests in that module passed after correction. No workflow was changed.
- Remaining pre-existing failure: test_verbose_log_candidate.VerboseCandidateTests.test_candidate_has_fresh_version_and_exact_source_verification expects project build 3; project.yml declares build 5, while the legacy candidate workflow still expects build 3. Release configuration was deliberately not altered. The full suite was not rerun after the expectation-only correction.

Next standalone gap identified: LocalVideoAudio.extract bounds decoded data and checks signal quality but does not compare decoded duration with the requested interval. Address with a portable duration policy plus Apple media regression fixtures; AVFoundation behavior cannot be established by these Python tests.

GeForce was untouched. Real-speech neural diarization, physical-iPhone behavior and listening verification remain unrun. No IPA or feed was published. The development commit skips push CI to avoid triggering Mac verification.
