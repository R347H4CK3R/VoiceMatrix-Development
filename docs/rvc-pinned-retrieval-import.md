# Pinned retrieval import and processing integration

## Behavior
The on-device preview source now accepts the exact VCTK p226 IVF1161 retrieval profile as well as the original diagnostic profile. RVCRetrievalAssets selects compiled-in filenames, lengths and hashes; the manifest only selects schema/profile and cannot supply authority for arbitrary hashes or paths. Missing manifests remain compatible with the original diagnostic folders. Unknown profiles, unsupported schema versions and oversized/malformed manifests fail.

Import copies the selected profile's three fixed files into a new private folder with bounded I/O, writes a canonical profile manifest and verifies the complete pack before committing installed.json. A failed copy/verification removes the new folder; the existing installed mapping is not changed. The existing feature's prior generated copy is replaced only after successful commit, and source/library folders are never deleted.

Processing resolves the installed profile and checks the exact synthesizer/index pair before loading. The VCTK voice can use only vctk-p226-ivf1161; the diagnostic voice can use only diagnostic-ivf149. Unknown model hashes remain rejected. The legacy diagnostic loader is preserved. The candidate loader streams the 139201536-byte vector bank into the already tested private snapshot backend; no whole-bank Float array is created. Conversion close explicitly releases its index before closing model sessions.

The view model enables retrieval controls only when a matching installed profile is present. A newly selected VCTK voice and Reset both use zero retrieval, even with its matching index installed. An explicitly selected nonzero strength is retained while the same model remains selected. The diagnostic default remains 0.75 when its matching pack is available. The UI notes extra temporary storage required by large packs.

## Exact candidate assets
Upstream revision 005c2f948ee9dafd7e3aa7f261b4c3a24beebeef, index SHA-256 7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50.

- centroids.f32: 3566592 bytes, SHA-256 36358a8e879e3f7d15222ab4771ad1e168479ee3fc80e7359097b381a0763dd1
- vectors.f32: 139201536 bytes, SHA-256 2326a4ca21cedbea61532a5c5b9fcba752f6de2ba9ff9cee5ecb8abda3a6bb98
- lists.json: 263091 bytes, SHA-256 68579a69b9cb75d7c84a8a956b6f6879e7c4b8e5d3e1554c0e4b2f72fde357eb

A private pack folder was prepared from the original full index, preserving 45313 genuine vectors and 1161 lists, with provenance and existing license/attribution files. It has not been published. Its manifest is schemaVersion 1, profile vctk-p226-ivf1161. Published build 6 does not support this new retrieval import.

## Verification
The exact-model/profile and default-policy tests first failed for missing behavior, then passed. 36 targeted existing portable tests passed after wiring; the additional manifest-admission test also passed (37 total). All app Swift files passed syntax parsing.

The actual full pack was hashed and loaded through the new portable loader. Native search reproduced all 24 expected neighbor IDs across three saved genuine encoder-feature rows. The test observed one open private vector snapshot while loaded, and no retained snapshot descriptor after the index was released. Cache directories remained empty because snapshots are unlinked after verification.

On disposable copies of the actual pack, a same-size one-byte change to each of centroids.f32, lists.json and vectors.f32 was rejected. Each failure left the cache empty. All original pack hashes were rechecked and preserved. These are real-file loader tests, not simulated success or an iPhone resource measurement.

The iOS importer invokes the same admission/loader code, with CryptoKit for SHA256. Portable tests use an independent system SHA256 process. Security-scoped Files access, the iOS import transaction, UI/actor interaction and AVFoundation/ONNX execution were not run here.

## Resource and release limits
Vector reads/cache remain bounded to 16 rows (49152 bytes), with transient replacement buffers and small returned rows. Centroids/lists are small fixed-size verified metadata. The complete vector snapshot still consumes about 139 MB of temporary disk storage during use, in addition to the installed pack; import temporarily needs both copies. Model tensors, neighbor outputs and the rest of the app add memory. No measured physical-iPhone peak RAM or latency claim is made.

The previous speech evidence remains mixed: 0.125 retrieval removed one known ASR regression, but additional held-out speaker-score changes were mixed. This wiring does not change quality defaults or establish intended voice likeness. Broader audio evaluation, human listening, Apple SDK compilation, physical-device memory/performance and native end-to-end audio with this import path remain outstanding.

No IPA, model pack or further preview was published. Build 6 remains the already published unfinished preview.
