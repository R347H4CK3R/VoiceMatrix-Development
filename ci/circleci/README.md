# Private CircleCI native UI candidate (NOT activated)

`native-ui.candidate.yml` is deliberately outside `.circleci/config.yml`. Its `run-native` parameter defaults to false. Nothing here creates an account, shares source, queues a build, enables billing, publishes an IPA, or claims free executor availability.

## Before activation

1. Complete authorized CircleCI signup and confirm repository visibility/access and the exact source revision. Keep private inputs private.
2. Confirm an eligible macOS Apple Silicon executor, available credits and no paid overage. No particular CircleCI plan or resource class has been verified. The config leaves resource class at the provider default; review it explicitly before running.
3. Confirm an available CircleCI Xcode 26 image. `26.0.1` is an editable candidate value, **not verified image availability**. The image must already include iOS 26 simulator runtime and iPhone 16 Plus device type.
4. Supply Python 3.12+, Homebrew, at least 15 GB free, and permitted outbound dependency downloads. The preflight checks these before assets are fetched. It never installs a simulator or changes system settings.
5. Validate with CircleCI CLI/API once access is available. Local validation covered YAML parsing and shell syntax, not the provider schema/account.
6. Only after approval copy the candidate to `.circleci/config.yml` in the chosen private CI branch and deliberately set `run-native: true` for the intended pipeline. No release step exists.

## What runs

The candidate translates the existing `character-ui-smoke.yml` shell steps, preserving build/test selectors, timeouts, restart of only the owned simulator, screenshot/log evidence and cleanup. GitHub environment propagation is changed to exported variables in CircleCI's BASH_ENV. Regenerate after changes with `python3 tools/prepare_circleci_native.py` (requires PyYAML).

It downloads the pinned diarization resources through `tools/bundle_diarization.py`, validates conversion inputs, and creates an original synthetic diagnostic voice. F5/OpenVoice markers are explicitly **UI availability fixtures**, not real models. SwiftPM dependencies and xcodegen are obtained using the same paths as the existing workflow.

Tests include playback, local policy/media boundaries, empty state/navigation, imported voice persistence and user naming/reset. Artifact paths include xcresults, logs and screenshots. Simulator identity is unique to the job; only that simulator is deleted.

## What this cannot verify

This is not a production IPA build or neural speech/voice quality test. It cannot establish automatic character identification, trained RVC, real F5 inference, music separation, phone memory/thermal behavior, physical-device installation, or indistinguishable voices. Real inference still requires the separately maintained native F5/local-pipeline diagnostics with genuine model assets and Metal support, then physical iPhone verification. No private trained ZIP is needed or uploaded for this UI job.
