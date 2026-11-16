# Build 10 candidate, unfinished preview

This candidate is not a 1.0 release. Build 9 remains available and unchanged.

Changes since build 9 include local catalog speech word checking with explicit unverified retained outputs, recoverable history and user-controlled deletion, distinct saved-file identities for separate attempts, and history sharing presentation correction. Failed recognition does not overwrite the previous checked output. Recognition can reject correct speech; unsupported lengths remain available for manual review. This does not repair voice generation errors or establish character likeness.

Reviewed native evidence covers positive, rejected and canceled production catalog speech paths, prior output preservation, retained request/reference identity and cleanup. Reviewed simulator evidence on bc2db8dd shows actual retained-history playback controls, two distinct saved files, a user-actionable original-file share sheet, cancel/delete/relaunch and retained reference. No external share destination was selected, and playback controls are not proof of audible fidelity. The full current-source regression remains a separate gate.

Packaging must generate and inspect the actual unsigned ARM64 build 10 IPA, preserve source proof, exact vendored source/notices and a single frozen dependency graph shared with native runtime checks. No package is published by this workflow. Exact artifact verification and separate publication review are still required. Historical workflows keep their historical build assertions; current aggregate build expectations advance to 10.

No physical iPhone verification, general input reliability, music/overlap separation, voice identity or indistinguishable cloning claim is made. The local model checker and its latency/resource cost still need real iPhone assessment.
