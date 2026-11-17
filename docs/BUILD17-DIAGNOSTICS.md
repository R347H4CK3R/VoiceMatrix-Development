# Build 17: privacy-safe acquisition diagnostics

Version 0.4.14 / build 17 is a diagnostic refinement of published 0.4.13 / build 16. It does not add source support, relax transport rules, or demonstrate a successful real-video download or voice likeness.

## Evidence and scope

Historical host probes retained three identical 195-byte HTML error pages, not audio/video. That finding does not diagnose an iPhone. No actual iPhone HTTP response was captured. The code previously collapsed resolver network/source failures into a generic response and media MIME failures into generic unsupported content.

The minimal change gives fixed allowlisted messages for resolver-network, resolver-source, resolver-engine, media-html, and media-type. It never echoes upstream error strings, response bodies, signed URLs, tokens, host addresses, or user media. Unknown resolver codes remain a fixed runtime failure. Existing acceptance criteria, response limits, URL/redirect validation, cancellation, retained attempts, and voice data remain unchanged. There is no diagnostic upload or telemetry.

A provider-reported HTML MIME type is classified as HTML; this is not content sniffing and does not establish which server or network generated the response. The ordinary page role still accepts HTML as before.

## Verification and release gates

Host wiring checks first failed on the previous mapping and then passed. Native XCTest must prove HTML rejection without success, preexisting sentinel preservation and retained attempt, distinct other MIME rejection, unchanged HTML page admission, and fixed resolver mappings without upstream secret disclosure. The dedicated actual-app gate requires all three named new tests as well as its existing minimum adapter count and failure/skip checks. All existing aggregate, full UI, speaker-handoff preservation, packaging and independent actual-IPA checks remain required on one exact source before publication.

Physical-iPhone connectivity, download, analysis, speech quality and likeness are not verified by synthetic tests. Existing local-file import and all previous voice/job data remain available. The existing optional paired-laptop metadata refresh is unchanged.
