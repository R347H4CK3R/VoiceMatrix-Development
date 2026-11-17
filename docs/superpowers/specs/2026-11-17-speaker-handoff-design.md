# Exact saved-speaker handoff

The user delegated continued standalone video-to-voice improvements. A retained multi-speaker job currently opens a generic library destination using whichever voice happens to be selected. Provide explicit per-speaker Make speech and Change my voice actions. This is navigation to existing local F5/OpenVoice routes, not new inference, training, download support or proof of likeness.

Approaches: automatic selection when history opens changes user state unexpectedly; generic library navigation leaves speaker ambiguity; explicit job/speaker-bound action is selected. Selection requires idle/active local studio, idle library/audio, current job identity, verified retained reference/preview receipts, and exactly one saved profile matching both voice ID and reference hash. A missing, changed or ambiguous profile preserves existing selection and files. Success selects only the matching profile and opens the requested mode, without starting synthesis or conversion. Library's usual later on-appearance refresh remains unchanged.

Scope: isolated local candidate based on published e5c239 build15. No version/release changes or upload in this task. No files deleted. Existing generic link is renamed Browse saved voices. Tests exercise real matching policy and native controller guards; iOS compile/UI required before any release.

Follow-on authorization: after source review, parent requested full native validation and truthful publication when ready. Candidate advances to 0.4.13/build16 with synchronized in-app notes and package/runtime identity. Existing published artifacts remain unchanged; publication requires exact-source gates, independent IPA verification and fresh catalog preservation.
