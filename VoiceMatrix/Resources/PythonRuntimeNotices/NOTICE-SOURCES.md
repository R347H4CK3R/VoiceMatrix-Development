# Bundled CPython support: dependency notice audit

Scope: the five dependencies named in the verified BeeWare Python3.13 iOS support b18 `VERSIONS` file, plus CPython's root license and upstream consolidated third-party license documentation. This is evidence-based packaging review, not a legal opinion or proof that every possible compiled source copyright has been independently inventoried.

Verified runtime version evidence:
- Python3.13.18, build b18
- BZip2 1.0.8-2
- libFFI 3.4.7-2
- mpdecimal4.0.0-2
- OpenSSL3.5.9-1
- XZ5.6.4-2

The suffixes are BeeWare build revisions. Upstream version notices fetched unmodified:

| Dependency | License/notice file | Primary source |
|---|---|---|
| OpenSSL3.5.9 | Apache2.0 | https://raw.githubusercontent.com/openssl/openssl/openssl-3.5.9/LICENSE.txt |
| libffi3.4.7 | MIT, copyright Anthony Green/Red Hat/others | https://raw.githubusercontent.com/libffi/libffi/v3.4.7/LICENSE |
| BZip2 1.0.8 | upstream permissive bzip2 license, Julian Seward attribution | LICENSE inside https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz |
| mpdecimal4.0.0 | BSD2Clause, Stefan Krah attribution | COPYRIGHT.txt inside https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-4.0.0.tar.gz |
| XZ5.6.4 liblzma | 0BSD | https://raw.githubusercontent.com/tukaani-project/xz/v5.6.4/COPYING and COPYING.0BSD |
| CPython3.13.18 | PSF and historical notices | exact bundled Python.xcframework/lib/python3.13/LICENSE.txt |
| CPython incorporated software | upstream consolidated notice document | https://raw.githubusercontent.com/python/cpython/v3.13.18/Doc/license.rst |

OpenSSL tag root listing was inspected: LICENSE.txt exists, no root NOTICE file was listed. XZ COPYING explicitly identifies liblzma as0BSD, while some scripts/build tools have different licenses. No `xz`, `xzgrep`, or `bzip2` command binaries were found in the inspected runtime framework; do not generalize liblzma's license to unrelated XZ build tools or scripts if later bundled.

Required integration: copy `RuntimeNotices/` into an app-bundled resource folder and make its notices available with the distribution. Preserve existing wheel licenses (yt-dlp core Unlicense; EJS includes MIT/ISC; certifi MPL2). Keep native Python/OpenSSL license files intact during resource stripping. `notice-hashes.json` records exact notice bytes for verification. No executable code or source media is included here.

Remaining verification: ensure the final IPA actually contains these resource files (inspect zip after archive), and retain the original upstream dependency license notices if runtime packaging changes. Source archives were fetched to inspect notices only; no downloaded source was built or executed.
