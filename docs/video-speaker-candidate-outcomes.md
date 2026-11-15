# Durable speaker-candidate outcomes

The standalone video workflow now creates a bounded candidate record for each selected speaker window before extraction. Records retain the source SHA-256, anonymous diarization label, exact start/end times and chronological outcomes. Reference and preview hashes cannot change midway through an attempt.

The actual workflow records:
- window selection and extraction;
- rejected extraction or sound-quality screening;
- absent reference speech;
- retained transcription and incompatible engine input;
- preview generation and word verification;
- absent preview speech or failed word-error gate;
- successful library import or reuse, bound to reference hash, preview hash and voice ID.

Previously silent no-speech/extraction branches now emit an actionable live-log message and retain their attempt evidence. The existing source, extracted references, previews and transcript/quality files are not deleted by this feature. Rejected candidates remain rejected; no diagnostic metric is promoted into voice identity or likeness approval.

## Storage and cancellation

LocalReferenceAttempt writes candidate-<UUID>.json in the existing private job folder. Each record has at most 16 events and 64 KiB, with bounded labels/reasons and validated hashes/IDs. Updates verify the existing source/window/history before atomically writing the next snapshot. A terminal saved/reused/rejected outcome cannot be overwritten. Saved/reused outcomes require both audio hashes and a voice ID.

Cancellation before an event commit preserves the last completed record. If inference or another unexpected operation fails, its last completed stage remains on disk alongside the job's existing failure/pause log; this feature does not invent a completed outcome. Resumed attempts get new IDs rather than overwriting old evidence.

## Tests

Seven targeted checks passed:
- Native candidate provenance, terminal-outcome and audio-hash binding tests, independently read as JSON by Python.
- Actual Swift speaker-window policy checks covering bounds and exclusion of overlapping speakers.
- Two native profile/library tests covering package validity, transcript association, existing-voice preservation, duplicate/tamper rejection and cancellation.
- Three existing source-contract checks for per-speaker result bindings and UI playback routing.

An additional cancellation scenario within the candidate test passed after being added: an attempted event on a cancelled Swift task leaves the previous file byte-for-byte unchanged. The candidate and speaker-window tests use controlled metadata/segments and do not run a neural diarizer. Swift frontend parsing passed for the changed video workflow and evidence type.

## Remaining verification

Real speaker-model execution still uses the bundled iOS diarization runtime and has not been executed in this Linux test environment. AVFoundation extraction, the complete video-to-F5 generation loop, physical-iPhone performance and listening/identity review remain unverified. Prior licensed speech/model provenance is unchanged; no new model or audio data was fabricated or published.

No IPA, preview, model package or source feed was released. This change adds traceable outcomes to genuine existing extraction and profile-creation branches; it does not train RVC voices or replace failed analysis with a stock voice.
