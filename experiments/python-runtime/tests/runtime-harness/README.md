# Native runtime cancellation test host (not run here)

Create a dedicated iOS app XCTest host containing VMPythonRuntime, its two C
headers and pinned Python SDK/stdlib. Its `app_packages` folder resource must be
THIS directory's fixture package, not production resolver code. Add
VMPythonRuntimeCancellationTests.m to its hosted unit test target. Run one test
process; runtime intentionally owns one interpreter/evaluator for process life.
Do not add this fixture to VoiceMatrix production sources or resource globs.

The valid fixture pauses at the actual CPython -> vm_webkit -> main dispatch
boundary by using a nonblocking fake native evaluator. Test verifies prelaunch
cancel, active cancel, post-cancel late reply, and successful next request despite
stale first-request cancellation. Removing cancelRequest would fail both the
prelaunch launch count and the paused valid request completion timeout. This is
not a WebKit test; run provider's separate real WebKit XCTest suite too.
