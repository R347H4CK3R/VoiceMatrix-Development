# VoiceMatrix physical audit, source-only plan

1. Preserve the exact production sources, pin the already-reviewed two-phase XCTest and app project by SHA-256, and render an isolated target spec, runner, and display. Test that any pin drift fails before output.
2. Replace XCTest wrappers only, fail closed on assertion failure, preserve local job/clip/voice checks and both turns, and prove the transformed runner retains the original report semantics. Root must use the audit container only.
3. Provide an explicit offline phase-one button and a phase-two button unlocked by a new process. Reject simulator and macOS execution. Save only in the test sandbox; share only allowlisted success aggregates and hashes if explicitly selected.
4. Stop with source and portable tests. No signing, installation, asset fetch/bundle, dispatch or publication. A future private staged IPA needs license clearance, exact pinned assets, native compile, side-by-side signer behavior, and deliberate user action on physical iPhone.
