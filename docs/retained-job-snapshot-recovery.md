# Retained job snapshots and restart recovery

The previous status writer could emit a job snapshot larger than the history loader's
256 KiB limit. A reproduced 160-event job with 1,900-character status entries exceeded
that limit. The job remained on disk but disappeared from history after restart.
An oversized non-event status could also replace the earlier usable snapshot.

The writer now bounds new snapshots to 256 KiB by trimming only the live event suffix.
Every update is still synchronized to the separate append-only event journal first.
The latest retained events stay in chronological order. If non-event metadata alone
exceeds the limit, writing fails and the previous atomic snapshot remains intact;
in-memory completion is not committed ahead of the disk write.

Read-only restart recovery accepts older snapshots up to 2 MiB, allowing oversized
snapshots produced by the old 160-event writer to be reopened. Reads reject non-regular
files, final symlinks, linked job folders, oversized files, invalid JSON, mismatched job
IDs and unsafe relative filenames. This does not repair corrupted JSON or delete files.
The app reports how many retained snapshots could not be reopened instead of silently
omitting those jobs without explanation. App-container parent directories remain trusted.

Small metadata reads remain available inside a cancelled job's cleanup path. They have
an explicit 2 MiB bound and nonblocking regular-file checks; source/media reads still
honor cancellation. A regression reproduced the cancelled-cleanup failure before this
exception was added.

Portable verification executes the production history loader and status-update method
against real Foundation files, including older oversized snapshots, oversized
files, symlinks, FIFOs, corrupt JSON, wrong job IDs, traversal filenames, cancellation,
warning counts, repaired test fixtures and retained-byte preservation. It also checks
that all 160 events remain in the durable journal after the live snapshot is trimmed.

```sh
python3 -m unittest tests.test_local_snapshot_recovery tests.test_local_completion_transaction tests.test_retained_media_reader -v
python3 tools/portable_studio_gate.py
```

These checks do not run SwiftUI, Apple model inference, physical iPhone storage handling
or the full iOS app. The UI warning is source-wired and syntax-checked; its native display
remains unverified. No voice pack, existing release, version number or source feed is
changed by this recovery work.
