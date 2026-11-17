# VoiceMatrix on-device resolver candidate

Native CPython calls `voicematrix_resolver.resolve(request_json)` serialized off-main. Request: `{"schemaVersion":1,"url":"https://youtu.be/abcdefghijk","authorized":true}`. Success returns schemaVersion/status=ready/parts; each part contains HTTPS URL, kind (combined/video/audio), extension and expected bytes. Failures return status=unavailable and a fixed error_code. Swift must independently validate URLs, hosts, redirects, file size, storage, cancellation, receipts and media decoding. Never log or publish returned signed URLs.

The resolver uses pinned yt-dlp 2026.10.26 and yt-dlp-ejs 0.8.0. Bundled source dependencies only; no downloaded Python code, external plugin, executable, laptop or server. Optional native `vm_webkit.evaluate(body,input_json)` runs ordinary player URL transformations in a bounded network-denied WebKit context. No upstream Apple plugin is bundled: its private KVC file-access configuration is deliberately not used. This code uses private yt-dlp APIs and requires revalidation before any upstream version change.

Only normal public WEB player responses with the requested identity, non-live content and no reported age/access restriction are eligible. Alternate client fallback, authentication, cookies, credential access, PO-token providers, DRM formats and manifests are disabled. This deliberately does not reproduce all yt-dlp behavior. Metadata-only/SABR-only player responses have no supported media plan and remain unsupported even with WebKit installed.

Python performs metadata requests only to exact HTTPS YouTube hosts. No proxy/cookie/auth handler; every redirect is validated before following, max5 redirects, max12 requests,4MB per body,12MB aggregate and90-second task budget checked between reads. Socket timeout20seconds. Native host must impose its own lifetime/cancellation control because platform DNS resolution may not honor Python socket deadlines. TLS verification is mandatory; this candidate explicitly loads its pinned bundled CA roots. No private credentials or provider response text cross the error boundary.

Only direct AVC/AAC MP4 or separate AVC video+AAC M4A, <=720p,3–1800seconds and<=512MiB total, with declared size, are returned. Swift handles download/mux/analysis as before. Generic WebM/AV1, HLS/DASH and arbitrary hosts are intentionally not accepted.

## Verification

`PYTHONPATH=<bundled-python-packages> python -m unittest discover -s tests`

22 tests pass with pinned packages in Linux, including actual yt-dlp extraction of a synthetic public-player fixture. Native WebKit/CPython tests are separate and not claimed by these tests. A publicWEB-only no-JS live probe of the reported source produced storyboard entries but zero media formats. The secure production transport cannot connect through this workspace's mandatory HTTP proxy because proxy use is disabled; this does not establish iPhone connectivity. No exact-link media download or native-device success is claimed.

## Source/license basis

- yt-dlp core source/wheel: Unlicense. https://github.com/yt-dlp/yt-dlp/tree/2026.10.26
- yt-dlp-ejs: Unlicense, with MIT `astring` and ISC `meriyah` notices in its bundled LICENSE. https://github.com/yt-dlp/ejs/tree/0.8.0
- Do not substitute PyInstaller binaries: additional bundled license obligations differ.
- Native runtime packaging owner must ship Python/OpenSSL/libffi and all bundled license notices.

## Cooperative cancellation

The resolver checks the native `vm_webkit.is_cancelled()` flag at entry, request admission/redirect, before and after opening/reading each metadata chunk, around extraction and native WebKit execution, and before returning a media plan. Cancellation returns the fixed `cancelled` code; late successful extraction results are discarded. A missing or failing cancellation method in an otherwise-present native module fails closed as `cancellation_unavailable`.

This does **not** forcibly interrupt Python DNS lookup or a socket call already blocked inside the OS. It stops the next request/read and closes an active response once the current call returns. The native runtime separately suppresses late completion and cancels the active WebKit request. Tests use controlled blocking read/open boundaries to verify cooperative stop and response closure; they do not establish native iPhone cancellation timing.

## Explicit TLS root bundle

Metadata HTTPS now uses `certifi` 2026.10.23, with the PEM SHA256 pinned to `2ef52ad56b4803e264045c915e55c236cbfa045b84b81efefc218a19eb44bd2b`. `_tls_context()` verifies version and root-bundle digest, then loads those exact bytes through `ssl.create_default_context(cadata=...)`. It does not fall back to an environment path or disable hostname/certificate verification. Missing/modified bundles fail closed as `trust_store_unavailable`. Updating the roots requires a reviewed dependency+digest update. Tests verify required peer/hostname checks and an in-memory handshake rejects a synthetic untrusted server certificate. This validates Linux OpenSSL behavior, not native-device TLS connectivity.
