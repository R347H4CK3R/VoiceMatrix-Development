# VoiceMatrix private development — Linux verification, 2026-11-14

This is a source development candidate, not completed VoiceMatrix 1.0.0 and not a new IPA.

## Established baseline

- Private repository: `R347H4CK3R/VoiceMatrix-Development`.
- Source branch: `import/voicematrix-40abec4`, commit `ff656089e7879a1e6a02be02bf24ccf5d00f7d05`, tree `64366ff4fb4e5a36d9f4e27588cef6d9a4cd7c50`.
- `main` was a one-file private-development placeholder, not the app baseline.
- All 1,101 baseline file blobs were recovered by exact Git blob hash or fetched at the pinned commit. Changes were compared against those hashes.
- Related Ghostline was already public, with inspected main at `2fc417bd73b5e13bb742c8f9de3139f69e4f80a6`; 833 files matched the private snapshot. No development source was sent there.
- The source already contained the standalone local studio, bundled-model adapters, retained per-speaker receipts and durable journal. The historical README described an older release; it is now clearly separated from current development status.

The snapshot-recovery continuation starts from private commit `370f2fdf7a5b5760dbc5dd95d8c006b68dfc3988`.

## Changes

1. Retained source validation now uses one bounded Foundation/POSIX reader for resume and acquisition digests. It opens without following a final symlink and without blocking on a FIFO, validates the opened regular-file descriptor and the 512 MiB production bound, reads in 1 MiB chunks, checks cancellation, and rejects growth/truncation. Existing hash comparisons remain authoritative. No source or voice is deleted. App-container parent directories remain trusted; this is not a general hostile-filesystem sandbox.
2. Diagnostic redaction now recognizes quoted multiword credential values and quoted JSON keys, and removes hidden controls before checking credential markers. The new synthetic regression failed against the previous implementation and passed after the fix. Both persisted events and displayed/exported pages are exercised. This remains defense in depth for status-only logs, not permission to log arbitrary secrets or transcripts.
3. The CircleCI candidate generator now reproduces the existing Python 3.12 setup, Xcode parameter, resource class and heredoc escaping. This fixes a pre-existing portable test failure. The installed `.circleci/config.yml` and its disabled-by-default native execution remain unchanged.
4. `python3 tools/portable_studio_gate.py` runs the focused studio regressions and fails if any are skipped. The bounded reader also joins the existing no-skip Foundation gate.
5. The continuation fixes retained jobs disappearing after restart when snapshots exceed the old read limit. New snapshots are bounded, old oversized snapshots receive bounded read-only recovery, unreadable jobs produce a visible warning, and cancellation cleanup keeps access to small history metadata. Full journals and previous atomic snapshots are preserved. See [snapshot recovery](retained-job-snapshot-recovery.md).

All 564 tracked blobs under `models/`, `LICENSES/` and `VoiceMatrix/Resources/` remain identical to the baseline. No real user voice packs, installed data, published IPA or feed history were modified.

## Verification in this turn

Environment: Linux, Python 3.12.14, Swift 6.1.3. The optional selector test uses the repository-pinned `yt-dlp==2026.10.26`, installed in a separate temporary directory. No model downloads or paid services were used.

- Focused portable studio gate: 36 tests passed, zero skips.
- Foundation policy gate: 6 tests passed, zero skips.
- Swift syntax parsing: all 58 app Swift files passed. This is not Apple SDK typechecking.
- Initial complete discovery: 744 tests, one pre-existing CircleCI template failure, five skips. The configuration defect was fixed and its three focused tests passed. The yt-dlp dependency was then made available for the final run.
- Continuation final complete discovery: **742 passed, 4 skipped, zero failures/errors** (746 discovered, 241.74 seconds). Skips: two Windows Job Object lifecycle tests, one Windows junction test, and the Apple Swift/CryptoKit selective-download contract. The actual pinned yt-dlp selector test passed without contacting a website.

The suite mixes real Foundation/file/SQLite/HTTP/media behavior with explicitly controlled neural, audio and UI boundaries. Synthetic fixtures and mocked neural workers are not real RVC training, model inference, intelligibility or character-likeness evidence.

Reproduce the focused checks with a real `swiftc` on PATH:

```sh
python3 tools/portable_studio_gate.py
python3 tools/native_policy_gate.py
```

Full discovery also needs the repository's Python test dependencies and FFmpeg:

```sh
python3 -m unittest discover -s tests -v
```

## Publication and remaining work

The existing Strata source already lists `voicematrix-v0.4.9-build3`, version 0.4.9 build 3, as its newest entry. Its URL and 1,305,715,047-byte size match the published asset; GitHub's reported SHA-256 matches the feed:
`390314b3270e5eea38fc1cb4b54233d3a71bae5438cb9ab6594fa10c97a95f75`.
This turn checked metadata, not a fresh download or execution of that 1.3 GB IPA. Its release targets `9ccce36958247a687a6386e72f09f36d1c0e69f0`, so it does not contain these new fixes.

The public feed is `https://raw.githubusercontent.com/R347H4CK3R/Ghostline/main/strata-source.json`.
No new feed entry was written: this Linux environment has not produced a new ARM64 iOS IPA. The source version metadata remains 0.4.9 build 3; a subsequent build must use a new build number and fresh provenance, never relabel the existing IPA as these changes or as 1.0.0.

Per the owner, Mac-runner verification was skipped. The exact changed candidate still needs Apple SDK compilation/packaging, native UI/audio/model checks, SideStore/Strata installation and physical iPhone memory, thermal, cancellation and offline behavior checks. Audio identity/likeness remains separately unverified.

Remaining product gaps in the baseline are broader than omitted tests: full on-device RVC training/conversion, reliable music separation, broad video-site acquisition and verified character identification are not completed by this change. Existing local F5 reference workflows are not relabeled as trained RVC or verified identities. The source tree contains model placeholders; a source-only build without the pinned model assets must not be distributed as a functional audio app.
