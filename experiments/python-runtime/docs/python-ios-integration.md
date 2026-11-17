# Embedded CPython integration candidate (NOT device-verified)

## Verified inputs

- Official CPython embedding guidance: https://docs.python.org/3.13/using/ios.html
- Maintainer distribution: https://github.com/beeware/Python-Apple-support
- Version tag `3.13-b18`, Python `3.13.18`, minimum iOS13; arm64 device,
  arm64/x86_64 simulator. Our app iOS26 target is above its minimum.
- Archive SHA256 `d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d`
  verified against downloaded bytes and GitHub release digest.
- Archive34,524,958 bytes. Unpacked common stdlib51MiB; device slice27MiB,
  simulator45MiB. Device slice includes headers/tools not all shipped; measure
  final IPA rather than advertising this as final size increase.
- SDK VERSIONS: BZip2 1.0.8-2; libFFI3.4.7-2; mpdecimal4.0.0-2;
  OpenSSL3.5.9-1; XZ5.6.4-2.

## XcodeGen integration to apply in the owner candidate

1. `python3 tools/prepare_python_runtime.py --destination Vendors/Python`
   before XcodeGen. Cache by exact SHA, never by mutable latest release.
2. Add `Vendors/Python/Python.xcframework` to app dependencies as `framework`,
   `embed: true`, `codeSign: true`. Keep SDK out of Git.
3. Add Objective-C `VMPythonRuntime.h/m` app sources and import header in app's
   Swift bridging header (`SWIFT_OBJC_BRIDGING_HEADER`). Objective-C ARC required.
4. Add audited pure Python dependencies and resolver as folder resource named
   `app_packages` (not flattened). No pip/external executables at app runtime.
5. Add shell phase `bash "$PROJECT_DIR/tools/install_python_runtime.sh"` after
   resources and before framework embedding/signing. Single ARCHS arm64 device;
   simulator active architecture only. Headers framework search path uses built
   Python.framework; `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER: NO`.
6. Initialize VMPythonRuntime on main with block forwarding to hardened
   VMWebKitChallengeProvider.evaluateScript:inputJSON:requestID:completion:, plus
   a canceller block forwarding to cancelRequest:. Runtime keeps
   one interpreter, serial worker queue and GIL lifetime. No Python call blocks
   main thread, no subprocess, environment ignores user site/PYTHONPATH.
7. Await resolveJSON asynchronously; native independently revalidates every
   selected URL, redirects, bounds and download/merge as before.

## Build/distribution blockers to verify before release

Linux has neither Apple SDK nor Objective-C Foundation toolchain. ObjC draft is
NOT compiled here. It is not wired into an app or called by UI. Package tests are
three checksum/preparer tests plus portable C lifetime/race tests, not full app tests.

BeeWare's SDK build utility relocates 68 stdlib `.so` files to separate signed
frameworks and adds `.fwork` markers. The install phase uses ad-hoc signing when
app signing is disabled. Hosted macOS/Xcode must verify all framework Mach-O
architectures, final relative paths and entitlements. SideStore must re-sign all
nested frameworks. Check seven-day refresh/install, launch, TLS `_ssl`, `hashlib`,
`zlib`, resolver import and WebKit bridge on physical iPhone. Simulator does not
prove SideStore signing. Preserve license resource and privacy manifests.

Run exact-source unit/UI and actual resolver tests before packaging, then inspect
IPA plist version/build, framework count and final checksum. No feature-ready or
specific URL success claim until native result observed.

No CI workflow is added here to avoid starting unreviewed 78MiB build input across
all existing gates. Gate can prepare the pinned SDK on an existing macOS26 runner
with installed Xcode26; no local laptop, paid runner upgrade or billing changes.

## Licensing release gate

CPython's source includes PSF license and embedded third-party notices in
`Python.xcframework/lib/python3.13/LICENSE.txt`. Keep it. The prebuilt SDK links
additional dependencies listed in VERSIONS; collect their exact-version licenses
from BeeWare source dependency recipes (not assume CPython LICENSE alone covers
OpenSSL/BZip2/libFFI/mpdecimal/XZ). Licensing audit remains incomplete and blocks
public binary release. yt-dlp source/wheel Unlicense (do not bundle desktop
PyInstaller GPL distribution); EJS and certificates retain respective notices.
The upstream Apple WebKit plugin Apache2 was reviewed but is NOT bundled: its
universal local-file access, private KVC and popup configuration are unacceptable
here. The app uses the separately hardened native provider instead.

## Bridge race regression verification

`VMChallengeLifetime.h` is the production lifecycle state helper. Its caller uses
a recursive request lock, so a synchronous provider error callback is safe and
expiration cannot interleave between launch guard and evaluator invocation.
Monotonic deadline applies both to launch and result acceptance. Semaphore timeout
closes acceptance before GIL reacquisition and always discards timeout output.
Cancellation carries its original UUID; the provider must ignore IDs not matching
its active request. Provider evaluation entry must return promptly (never wait
for JavaScript synchronously).

Locally passed:
```sh
cc -std=c11 -Wall -Wextra -Werror tests/test_challenge_lifetime.c -o /tmp/vm-lifetime && /tmp/vm-lifetime
cc -std=c11 -Wall -Wextra -Werror -pthread tests/test_challenge_race.c -o /tmp/vm-race && /tmp/vm-race
python tools/test_python_runtime_package.py
```
Threaded test repeats delayed main dispatch and post-expiration completion1,000
times each. This verifies the actual shared C state helper, not Apple's dispatch
or Objective-C/Python integration, which still requires hosted native tests.

Whole-resolver cancellation: `resolveJSON:completion:` now returns a UUID. Store
that ID for the user operation and call runtime `cancelRequest:` on cancel or
backgrounding. It sets cooperative cancellation, wakes a waiting JS bridge, and
cancels only that bridge UUID at the provider. Native drops any later output.
Python's `vm_webkit.is_cancelled()` is checked by the resolver at network/read/
extraction checkpoints. This does not forcibly interrupt an OS DNS call; the
worker remains serial until it returns. Never claim immediate interruption of
underlying network work. Identity registration remains until completion dispatch.

The Objective-C cancellation XCTest is authored but NOT run. Real Apple GCD,
Python-GIL and Swift/WebKit race tests remain required in native CI. Neither the
portable tests nor source inspection establishes that platform boundary works.

Worker ownership is enforced through a pthread TLS key, not a global request
pointer. A child Python thread has no request context: `is_cancelled()` returns
true and `evaluate()` raises `resolver_worker_required`. The context is cleared
before the worker finishes. Portable production TLS helper test verifies child
thread isolation and clearing. Registry removal on main is the completion commit
point; cancellation after removal is a no-op because delivery has begun.

The native XCTest now uses a VALID deterministic resolver fixture paused at the
actual embedded Python/Objective-C bridge. See tests/runtime-harness/README.md.
It replaces the invalid-input-only test. Fixture must be confined to the dedicated
test host and NEVER bundled into production VoiceMatrix. Native execution remains
unverified. Resolver cooperative checkpoint implementation is owned separately;
verify its exact source before integrating, rather than assuming the builtin
alone interrupts networking.

## Packaged Python dependencies and trust roots

`tools/requirements-ios-resolver.txt` pins hashes for yt-dlp2026.10.26,
yt-dlp-ejs0.8.0 and certifi2026.10.23. Installed with `pip --no-index --no-deps
--require-hashes` from verified wheels into app_packages; generated CLI launcher
and Python caches removed. Keep wheel license notices under dist-info/licenses.
Certifi wheel SHA256: e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1,
verified against official PyPI version metadata. Bundled cacert.pem SHA256:
2ef52ad56b4803e264045c915e55c236cbfa045b84b81efefc218a19eb44bd2b.
Linux `ssl.create_default_context(cafile=certifi.where())` loaded119 CA roots,
CERT_REQUIRED and check_hostname true. This is NOT an iOS TLS verification.

Explicit trust configuration is now integrated. Resolver SHA256:
02cbf2e67bc76e11a7048808f43b3f5dd3e3c82f41ee6a89b11cb4966350ada3.
`_tls_context` validates certifi version plus PEM digest, then loads those verified
bytes via `ssl.create_default_context(cadata=...)`. HTTPSHandler uses that
context; missing/changed roots fail closed, no environment/system-root fallback.
Combined local verification:22 resolver tests,3 SDK tests,3 compiled C test
programs pass. TLS suite includes a memory-BIO handshake rejecting an untrusted
self-signed server. All verification is Linux-only, not iOS/SideStore evidence.

## Separate native harness prepared (not dispatched)

`runtime-harness.yml` creates a small distinct XcodeGen app/test host; it does not
alter build13, its version, assets or distribution feeds. `tools/test_native_runtime.sh`
fetches the pinned SDK, builds this host and runs actual simulator ObjC/Python and
WebKit XCTest suites. The fixture app_packages is deliberate test-only and does
not load production resolver. Separate host Python policy tests load production
resolver and pinned wheels. The prepared manual-only workflow uses existing
standard macos26 runners and has read-only repository permissions. No workflow
was uploaded or dispatched. Parent must select separate feature branch and
publish/dispatch deliberately; current build13 queue remains separate.

XcodeGen postBuildScripts runs after resources and embedding; Python extension
frameworks are separately ad-hoc signed by the install step. This differs from
CPython's suggested before-embed placement but doesn't modify Python.framework;
verify final product layout on native run. No signing-policy change is applied.

## Native harness review corrections

Dependencies are rebuilt from hash-pinned wheels into fresh `.runtime-stage`
production/harness trees. Neither pip nor test imports use preexisting checked-in
installed modules. Native host includes pinned production packages plus a clearly
isolated test wrapper, which now imports yt-dlp/EJS/certifi/_ssl and production
resolver trust configuration. The native test then crosses real CPython ->
Objective-C -> Swift WebKit -> JSON return; cancellation still uses a deterministic
paused callback first. This native test is authored, NOT executed locally.

Workflow action revisions are pinned commit SHAs; XcodeGen2.44.1 archive SHA256
`a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73` was checked
against the official release and downloaded bytes. No Homebrew latest install.
Only an available iPhone on iOS26 is selected; absent runtime fails rather than
silently testing iOS18. SDK packaging test requires its downloaded archive and
cannot skip. Package staging and final app copy remove bytecode caches.

Updated local checks:24 Python policy/selector tests plus3 required SDK tests pass;
workflow YAML and shell syntax checked. Controlled-network iOS verification,
Apple compilation and XCTest execution remain separate required gates. None has
been claimed complete and no workflow has been uploaded or dispatched.
