# Durable diagnostic RVC previews

The user delegated design choices and implementation. This extends the existing
hash-pinned evaluation converter, not voice training, identification, separation,
or a voice-quality claim. Existing release/preview references stay unchanged.

## Approaches and choice
- Scanning WAV filenames alone is small but cannot bind source/model/settings or
  distinguish partial output. Rejected.
- A shared database adds migration and corruption coupling. Unnecessary here.
- **Chosen:** bounded, versioned atomic per-result JSON receipts beside existing
  completed WAVs; independent safe listing and explicit verified action snapshots.

Completed WAV and receipt are retained permanently by this workflow. Receipt
publication is the irreversible commit boundary. Late cancellation never deletes
committed history. Failed publication leaves the complete WAV untouched and
reports an unindexed-file recovery notice, never inventing provenance for it.

Receipts bind relative generated filename, SHA256/bytes, source input identity,
verified encoder/synthesizer/retrieval identities, captured settings and timing.
Listing reads only bounded receipts and output file metadata; selection rechecks
receipt, safely hashes the output and makes a private verified snapshot before
playback/save/share is exposed. No URL/path from receipt is trusted. Reject
symlinks, FIFOs, malformed/out-of-bounds metadata and changed files. Limit scans
and receipt counts; do not delete or rewrite unknown/legacy files.

History recovery is separate from model installation refresh, requires no models,
never auto-converts/uploads/plays, and remains explicitly diagnostic. UI errors
are truthful and prior selected/results stay available where safe.

## Implemented bounds and verification limits
- At most 200 indexed receipts and 1,024 inspected entries; a full history refuses publication but keeps the completed audio.
- Receipt limit 16 KiB; original and copied audio limit 800 MB / 2 hours, canonical mono PCM16 WAV only.
- Action snapshots are private and retained, not deleted while a share sheet might use them. Copies are keyed by receipt UUID and SHA-256 and are freshly hash-verified on every selection. Repeated opens reuse the same copy. Corrupt or linked copies are rejected without overwrite. New copies are bounded by 200 directories / 1.6 GB total, a 1,024-entry scan, and 64 MB free space beyond the requested copy. A clear bound notice is shown; there is no automatic cache reclamation.
- Snapshot construction uses a private `.rvc-action-staging-UUID` directory and atomic exclusive directory promotion only after hashing, synchronizing and rechecking the receipt. Interrupted empty/partial staging is retained and counted (up to 16 attempts, within the same 1.6 GB total), never exposed as playable or silently adopted. An existing requested copy is verified before unrelated cache scans so damaged neighbors cannot block valid reuse.
- History integrity verifies bytes, not voice quality, human identity, or consent. Existing model authorization remains unchanged.
- Linux checks validate source structure only. Native filesystem, app compilation, and simulator UI remain mandatory before a completion claim. Simulator test covers navigation and empty history across relaunch, not conversion or playback.
