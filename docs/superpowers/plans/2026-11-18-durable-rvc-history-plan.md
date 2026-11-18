# Implementation and verification

1. Add native filesystem regressions first for receipt publication/relaunch,
   verification, malformed data, symlinks/FIFOs, corruption, cancellation,
   overwrite preservation and action snapshots.
2. Implement bounded CryptoKit-backed history store using RetainedMediaReader;
   atomic non-overwriting receipt publication and safe private snapshots.
3. Capture input/model identity and settings in existing conversion; publish only
   after successful conversion, preserving output on receipt failure/late cancel.
4. Independently load history; explicit leased snapshot selection; show durable
   diagnostic list and expose AudioActions only for verified snapshots.
5. Run focused/native tests, UI source contracts and complete suite. Add native
   CI and simulator UI coverage where feasible. No packaging trigger or push here.
6. Independent review; parent handles push and exact-commit CI. Distinguish local
   static checks, macOS filesystem tests, simulator UI and physical-phone evidence.
