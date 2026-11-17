# Fresh acquisition after retained URL failure

Goal: make a stalled website acquisition recoverable without discarding retained work or mixing refreshed streams with earlier tracks. Existing Resume keeps the original acquisition receipt and signed stream URLs. Those URLs can expire; repeating Resume cannot obtain a fresh plan.

Approaches considered: (1) silently refresh the existing receipt, rejected because original tracks could mix with a changed source and cause repeated network requests; (2) force manual URL re-entry, existing but unnecessarily difficult; (3) explicit confirmed fresh attempt in a new job, selected as the smallest safe improvement.

Design: offer a fresh-attempt action only for an unfinished URL job without retained source. Confirm it will contact the original source again and retain previous files. Tie confirmation to the job UUID, verify original/normalized URL identity, use existing new-job storage/network gates, and do nothing on cancel, stale confirmation, busy/inactive state, or missing authorization. Never use cached googlevideo links as original input. Do not auto-retry or weaken downloader restrictions. A fresh attempt may still fail; no universal download/voice-cloning claim.

Scope: local candidate only, no release/version/catalog changes in this step. Native iOS compile/UI checks required before shipping.
