# Raw-overlap guard (unpublished candidate)

The candidate retains segmentation activity before speaker clustering. This is a
conservative reference-crop veto, not voice separation or character identification.
It does not change model weights, clustering, or reconstruction output.

## Evidence and safety

Analysis policy 5 stores source SHA-256, model revision, frame timing, and raw
nearest-even expected-speaker counts. Frames with two or more predicted speakers
or missing coverage veto intersecting candidate crops. Stored windows must match
the deterministic candidate selection plus this veto exactly. Evidence is bounded
and source-bound; the media hash is checked before and after processing.

Older valid analysis is checked under its original policy and reanalyzed before
new references are generated. Any fresh analysis clears only the job's associations
to earlier references/previews. Existing library profiles and retained files remain
untouched. This reset also applies when prior analysis metadata is missing, so a
resume cannot silently reuse older assets lacking current overlap provenance.

## Limitations

This detector can miss overlap, including quiet competing speech. Earlier controlled
synthetic mixtures exposed a quiet-tail false negative. A crop passing this veto is
not proof of a single speaker, perceptual likeness, clean music removal, or separation.
The sound-quality screen is separate and does not establish speaker exclusivity.
Historical profiles are not retroactively certified by the new analysis policy.

## Verification status

This is a reviewed draft, not a new release. Linux source, integrity, and wiring checks pass. The actual Foundation-compatible
Swift policy, retained-analysis validation, missing-metadata reset, and legacy
migration tests also pass with Swift 6.0.3 on Linux (17 focused tests). This does
not compile or execute the CoreML adapter or iOS app. Actual current integration
still requires adapter compilation/inference, controlled mixture and clean-control
screening, and pipeline regression tests. The owner subsequently authorized hosted macOS build/testing for publication.
Build12 adds exact-source native integration and controlled mixture gates; their results remain pending.
The published build 11 remains unchanged.
