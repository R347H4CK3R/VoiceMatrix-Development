# Apple extraction investigation — 2026-11-15

Instrumented macOS run 43676149574 reproduced the failure on the first 0.5-second, 44.1 kHz stereo WAV extraction. AVAssetReader completed (status 2), error nil, producing 23,982 PCM bytes = 11,991 mono 24 kHz frames. The strict minimum byte guard raised unreadable before the existing 50 ms duration policy could run. No decoding failure occurred.

The fix separates reader status from duration validation and applies the existing 1,200-frame tolerance at the 0.5-second requested boundary too. Actual returned duration remains derived from actual PCM; no padding or fabricated samples are added. Maximum size, timestamp, clipping, energy and short-track rejection remain enforced.

A regression at 11,991 frames failed before the change and passed after it. The 10,800-frame tolerance boundary passes; 10,799 fails. All 12 focused local-video tests pass with the Linux Swift compiler explicitly on PATH. Four real-speaker evaluator tests also pass.

Mac rerun 43676371840 passed complete-media requests (0,0.5), (0,0.501), (0.2,1), (1.5,0.5), and rejected the short audio track. It then failed a separate probe assertion assuming the offset track range starts at 0.2. The follow-up checks nonempty media edits instead, logging their starts; its result must be reviewed separately.

CoreML run 43676148941 staged and verified all models and speech, but failed manifest compilation: macOS.v15 requires PackageDescription 6 while the probe selected 5.10. The probe now uses the supported string version 15.0; local swift package dump-package succeeds. Run 43676371848 is the actual production-adapter rerun; do not infer success from artifact verification or local evaluator checks.

These are macOS host and Linux tests, not physical iPhone, voice identity or human listening verification.

Follow-up run 43676601817 proved the offset fixture contains a nonempty media edit starting at 0.2 seconds. AVFoundation nevertheless emitted a continuous full-second PCM stream from zero, masking the empty edit with silence. The production extractor now rejects empty target-edit intersections longer than the existing 50 ms tolerance before decoding; this is checked in the build 7 packaging gate.

CoreML rerun 43676371848 PASSED. The actual production adapter compiled against pinned FluidAudio, processed 26 chunks, saved its analysis and passed the independent known-source mapping: S1 -> A, S2 -> B. Input bytes remained unchanged. This is real native macOS model execution, not merely artifact hashing, but it is one fixture and not phone or voice-generation validation.

The user subsequently authorized publishing an unfinished usable preview by tonight. Build 7 run 43676875745 is pinned to e5eaf98da5ac5e69505dc74847cd8821298e0a2b; publication to Strata is gated on that exact run, package identity and SHA-256. Do not describe publication as complete until both the release and feed are checked.

Final release gate: build 7 run 43676875745 succeeded. Its actual AVFoundation regression passed all complete/start/end/minimum-duration cases, rejected short media and empty-edit offset media, accepted aligned offset media, and confirmed source bytes unchanged. The ARM64 iPhone release compiled and its package/assets passed inspection.

Strata publication run 43676949135 succeeded. Both source.json and strata-source.json now list 0.4.9 build 7 first and retain build 6. Published size: 1,314,415,309 bytes. SHA-256: b96922a202f9d53af4b0e8cb980409654870ce2759118d2f52f6fc1db8252443. Public URL: https://github.com/R347H4CK3R/Ghostline/releases/download/voicematrix-v0.4.9-build7/VoiceMatrix-0.4.9-build7.ipa

Additional evidence: bundled ASR run 43676875656 passed real recognition with networking denied. Two Linux compiled reference-profile/library tests passed preservation, duplicate, tamper, format and cancellation checks. The simulator app/test build succeeded, but UI run 43676875671 had not completed at this report. Full local-pipeline Mac diagnostic 43676875677 failed to compile because its source list omitted LocalReferenceAttempt; the diagnostic manifest now includes that and LocalVoiceProfilePackage on the development branch, but the repair has not yet had an Apple rerun. The iPhone target already included all VoiceMatrix sources and compiled successfully.

This remains an unfinished preview. Physical iPhone, complete end-to-end generation, human listening and likeness are unverified. No full 1.0.0 completion claim is justified.
