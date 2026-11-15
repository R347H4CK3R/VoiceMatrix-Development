# Diagnostic trigger policy provenance

Both diagnostics exclude `codex/iphone-build4`, `codex/iphone-build5`, and `candidate/voicematrix-0.4.9` from push triggers. **Only bundled-ASR additionally excludes `codex/rvc-conversion-controls`; standalone-pipeline allows that branch.**

Historical commit [34d74e18](https://github.com/R347H4CK3R/VoiceMatrix-Development/commit/34d74e18f8ea9251ccacfd4e466ac789e9cfd4ed) explicitly added controls suppression to both workflows. Later commit [457128e8](https://github.com/R347H4CK3R/VoiceMatrix-Development/commit/457128e8592b40f1d71484fef8abaabb9574bb55) removed it from standalone-pipeline only, to rerun the repaired diagnostic with its asset cache. Imported baseline 962c04e preserves this difference, but its regression incorrectly expected the same list for both workflows.

This correction asserts each exact current exclusion list, explicitly checks that standalone-pipeline runs on the controls branch, and adds positive controls for similarly named branches and the integration branch. No workflow filter or runtime acceptance criterion changes.

Tradeoff: pushes to the controls branch automatically run eligible standalone-pipeline diagnostics, but not bundled-ASR diagnostics. Manual and reusable calls remain available for both. The candidate aggregate still requires both reusable diagnostics. Similarly named and integration branches are eligible when the existing source-path filter matches. Passing this policy test is not evidence that native code or a release works.
