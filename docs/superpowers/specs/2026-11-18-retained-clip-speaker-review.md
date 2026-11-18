# Retained clip speaker-turn review

## Authorized scope
Add a separate on-device analysis-only review for a hash-verified retained clip, 3–10 seconds. Reuse bundled LocalSpeakerDiarization and its model/overlap policy. No new models/downloaders, credentials, network fallback, generation, voice/reference creation, training, automatic identification, release or feed changes.

## Minimal design
Offer an explicit Find speaker turns action after preparing a retained clip, separately from separation. Require fresh authorization for this action and an exclusive existing audio processing lease. Canonical owned clip receipt and SHA must validate before and after analysis. Reuse LocalSpeakerDiarization.analyze directly, not LocalVideoStudio.run. Validate the returned current-policy evidence and rawOverlap.sourceSHA256. Cancellation, backgrounding, navigation or source changes must prevent late publication and release the lease.

Persist a bounded atomic sidecar outside immutable clip receipt/media files. Bind it to clip identity/hash, canonical analysis digest, model revision and policy. Labels are user-entered aliases bound to this exact clip+analysis+speaker, 1–80 characters with no line breaks/control characters. No cross-clip matching or fake library voices. Reject changed/corrupt evidence without deleting original data; never trust a cached name independently of its evidence.

Show local S1/S2 as model guesses with timestamped turns, overlap/no-clean-window states, and optional user labels. User may listen to source for review. No identity/confidence percentage claim. Clips shorter than3s are unsupported for analysis without changing extraction's0.5–10s scope. Silence, low quality or overlap must produce an honest insufficient/overlapping evidence state, not invented clean speakers; distinguish model turns from eligibility as a usable reference. Existing reference policy requires≥3s clean windows after trimming and stays unchanged.

## Acceptance boundaries
Native offline inference on genuine bounded licensed speech fixtures, source/receipt/voice library unchanged, durable label binding, cancellation and stale-result rejection, and simulator UX verification required before preview packaging. Physical device quality and speaker identity remain unverified. Current unsigned preview and all public feeds are untouched.
