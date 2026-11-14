# Private native CircleCI validation

Recovered baseline: `99e3e0c` (includes candidate v6 `5130a2f`).
Native configuration: `.circleci/config.yml`; this is not GitHub Actions compatibility mode.
Set pipeline parameter `run-native=true` manually after confirming a private repository and remaining free credits. Default false prevents automatic spending. No release, signing, catalog, or payment step is present.

Executor: `m4pro.medium`, Xcode `26.4.1`, listed by CircleCI documentation at https://circleci.com/docs/guides/execute/using-macos/ . The old 26.0.1 candidate image is not listed currently. Account eligibility and actual provisioning are not yet verified. Do not enable paid credits or retries automatically.

The preflight requires Apple Silicon, Python >=3.12, Xcode >=26, an installed iOS26 runtime, iPhone16Plus simulator type, and 15GB free. It refuses missing resources instead of downloading runtime images. Package source revisions and diarization downloads are pinned; diarization bytes are hash verified. XcodeGen is installed through Homebrew. Full inference models are deliberately absent; UI availability JSON and synthetic audio are test fixtures, NOT functioning cloned voices or a release IPA.

Runs the existing native UI and unit gate, collects logs/xcresults/screenshots, cleans only its own simulator. Run-step no-output timeout is 20 minutes, not a total credit cap. Check credits before starting and cancel at the agreed free budget. This gate alone cannot certify VoiceMatrix1.0.0 or end-to-end synthesis.

Local checks: Python tests and Bash parsing only. Native Xcode build and CircleCI server-side config validation still required. Do not push this branch into public Ghostline: GitHub branches inherit repository visibility. A private VoiceMatrix repository is required first.
