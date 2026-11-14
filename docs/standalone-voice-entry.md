# Standalone entry from Voices

The Voices tab previously sent empty-library users to a laptop catalog even though Video Voice Studio was available elsewhere in the app. Voices now directly links to the existing on-device video/audio creation screen. The link respects existing recording/processing activity. Initial status and empty-picker guidance describe on-device creation and folder import first; existing optional laptop catalog, downloaded packs, import and sync remain unchanged.

Verification: source-wiring regression checks and Swift syntax parsing passed. A native UI test was added to CharacterEmptyStateUITests to navigate from Voices into Video Voice Studio without pairing, and inspect the source controls. That test has not been run in this Linux environment. This change does not establish synthesis availability, voice likeness, or native device performance.

Review also identified stale first-launch instructions requiring a folder. The tutorial now offers on-device creation or import. Final tutorial wording has source assertions and syntax validation; native tutorial layout remains unverified.
