# Direct creation of reference voices

The Voices tab now has **Create voice from recording**. The user records or imports 0.5–10 seconds of speech, listens to the reference, enters a name and the exact spoken words, confirms permission to use the recording, and chooses **Save and select voice**. No diagnostic pack, laptop catalog, diarization model or automatic transcription is required for this route.

This creates a real reference profile compatible with the existing F5 speech and OpenVoice conversion paths. It does not train an RVC model, fabricate an embedding, select an unrelated evaluation voice or claim verified resemblance.

## Integration

CreateReferenceVoiceView uses the existing bounded Recorder and playback controls. CharacterLibrary.createReferenceVoice privately copies the selected recording before asynchronous work so navigating away cannot remove its input. It acquires the shared processing lease and library-generation owner, cancels optional laptop sync, releases warm speech models, extracts a canonical mono 24 kHz reference, and builds a normal voice collection. The existing CharacterFolderStore validates and atomically imports that collection. The imported profile is automatically selected for the existing Make Speech and Change My Voice actions.

Source copies are limited to 32 MiB; the direct audio duration is bounded to 0.5–10.01 seconds. Extraction retains the existing single-track, audible/non-clipping and maximum-buffer checks. Package generation admits canonical PCM16 audio only, limits it to 15 seconds to match the library contract, limits names to 80 characters and transcripts to the shared F5 limit of 512 UTF-8 bytes, validates the supplied SHA-256 format, and checks cancellation before admission. Actual iOS hashing uses CryptoKit.

Temporary files are removed on success or failure. Existing immutable voice revisions are preserved. Duplicate references and changed transcripts retain the library's existing rejection behavior. After a completed atomic import, late cancellation is not reported as if the saved profile were discarded.

A build missing the shared speech engine can still save a reference; the UI explicitly states that speech generation needs that engine. Saving a reference does not establish that the engine runs correctly on a phone.

## Verification

Two portable tests passed:
1. Package construction, independent Python WAV/schema/hash round-trip, malformed metadata/audio rejection, post-hash cancellation and existing-directory preservation.
2. Import through the actual CharacterFolderStore, loading the new voice beside an earlier voice, reference retrieval, duplicate rejection, corrupted-reference rejection and cancelled-import preservation. Python independently verifies each saved revision and reference hash.

The second test uses a test-only Linux module exposing the small CryptoKit SHA256 API needed by the store. It delegates hashing to the real /usr/bin/sha256sum executable; it is not included in app sources and is not Apple CryptoKit validation. Production CharacterFolderStore is used unchanged. Synthetic tone fixtures test packaging/storage only, not voice quality.

Swift frontend parsing passed for all changed UI, library, media and package files. Apple SDK typechecking, navigation/microphone behavior and end-to-end F5/OpenVoice inference with a newly created reference remain unrun. No listening or physical-iPhone result is claimed.

## Remaining blockers

- Compile and exercise the new UI and AVFoundation extraction on iOS.
- Verify a saved user reference through actual on-device speech generation and voice changing, including cancellation and storage failures.
- Evaluate naturalness and target resemblance by listening; prior RVC benchmark results do not qualify this separate reference-conditioned engine.
- Arbitrary user-trained RVC model creation/export is still not implemented. This feature uses the app's existing reference-conditioned engines.

No new IPA, preview, model asset or source-feed update was published. Existing voice files and model licenses remain unchanged.
