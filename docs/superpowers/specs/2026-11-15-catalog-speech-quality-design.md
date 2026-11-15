# Catalog speech word checks

Normal catalog speech currently publishes rendered audio without recognition, unlike studio import previews. A retained two-reader case reproducibly added an extra spoken word. No automatic transcript correction is justified.

Use the existing bundled recognizer on the final rendered WAV, after unloading F5. One attempt, no network, existing 30-second/8-MiB input bounds and 45-second timeout. Require usable text, matching audio/transcript hashes and WER <=0.1 before promoting to normal output. This is an automated word check, not likeness or guaranteed correctness.

Rejected, unsupported (including longer speech), canceled-after-render, and unavailable-ASR results remain separately available under explicit “Review unverified audio.” Do not replace previous good output on failure. Show ASR uncertainty, allow deliberate playback/export without promoting the item to checked. Keep rendered bytes and a local receipt in Application Support; no automatic trimming, regeneration, transcript insertion, deletion, or remote fallback. Prevent new generation once retained history exceeds 256 MiB; reserve disk headroom. Existing pitch/speed choices remain supported but may need manual review.

Alternatives rejected: silently accept after ASR failure; block all long speech; automatically prepend a guessed word; run a second large recognizer permanently. Added latency is one local recognition pass and F5 cold loading on next request. Native latency and physical-device memory still require measurement.

Tests: strict policy/hash negatives; unsupported and recognizer failure yield unverified; cancellation preserves rendered bytes and prior output; final output promotion follows verification only; target membership; actual Apple compilation and controlled accepted/rejected output checks before integration. No release until review and runtime evidence.

Review amendments: persist voice/reference/request/controls identity and timestamp before processing; expose recoverable paged history with explicit playback/export and confirmed deletion. Never auto-promote history on reload; label stored results historical. Cancellation is explicitly unverified. Deletion clears matching current bindings after success and is blocked during processing. Current pending audio requires both voice ID and reference hash. Native retained-audio lifecycle test and iPhone compile are required before integration.
