# Local completion status recovery

The standalone studio commits `Job.completed` in the same in-memory snapshot as its final durable status. It must not set the flag before the journal append and atomic `job.json` write both succeed. Otherwise a failed final write could leave an in-memory completed job that cannot be resumed.

`tests/test_local_completion_transaction.py` compiles the exact production update method and final completion statements in a minimal Foundation host. The journal is the real `LocalStudioJournal`; filesystem failures are real directories occupying the expected journal/snapshot filenames. It checks failed writes retain a resumable job, repaired writes can retry, successful completion agrees with the persisted snapshot, and unresolved speakers remain incomplete.

The regression failed on both journal and snapshot failure cases before the repair. Native whole-coordinator, Apple filesystem behavior, app UI and physical iPhone verification remain separate requirements. This is not a power-loss durability guarantee. If an append succeeded but the snapshot write failed, that append remains retained; it is not silently deleted.

Run with an installed Swift toolchain:

```
python -m unittest tests.test_local_completion_transaction -v
```
