# File-backed full-index retrieval and broader speech evaluation

## Implemented
RVCDiskVectorBank streams a trusted little-endian float32 bank into a private snapshot, checks all values for finiteness, validates exact length and a caller-supplied streaming SHA256 result, then keeps an open descriptor after unlinking its pathname. Mutating the original import cannot change the snapshot. Failures and cancellation clean up the temporary directory. It rejects symlinks, invalid sizes/counts, nonfinite values and incorrect digests.

The cache holds 16 rows (49152 bytes); each read block is also at most 49152 bytes. A replacement read may coexist briefly with the old cache, and returned rows allocate 3072 bytes. These are bounded vector I/O buffers, not a claim that the whole app uses 48 KiB. The snapshot occupies the full vector-bank size on disk while its descriptor is alive. Centroids, lists, model tensors and returned neighbors still require memory.

RVCNativeRetrieval has an explicit file-backed initializer, bounded to the store's maximum 50000 vectors and 2048 lists. It uses the existing top-eight ordering, distance computation, nprobe=1 behavior, sparse fallback and cancellation. The legacy array initializer and its existing limits remain unchanged. This backend is not connected to the user-facing pack importer; production hash allowlists and model/index pairing guards have not been widened. A real CryptoKit SHA256 accumulator and pinned pack manifest are still required at the eventual iOS import boundary. The storage API's digest argument is not itself model admission.

## Actual index verification
Used the exact VCTK p226 index SHA-256 7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50 from the existing pinned upstream revision. It has 45313 vectors, 768 dimensions and 1161 IVF lists. Reconstructed genuine rows in 256-row export blocks; no duplicated, fabricated or downsampled bank.

Exported vector bytes: 139201536; SHA-256 2326a4ca21cedbea61532a5c5b9fcba752f6de2ba9ff9cee5ecb8abda3a6bb98. Native snapshot hashing/finiteness validation processed the complete file. Direct row checks covered rows 0, 15, 16, 22656 and 45312, including cache boundaries and the final partial block. An uncached row remained exact after truncating a separate test import; the original index and exported bank were preserved.

Native file-backed search on all 45313 vectors/1161 lists matched FAISS's 24 neighbor IDs across three genuine saved encoder-feature rows. Every returned distance was within absolute tolerance 0.001. This is a numerical search test, not native end-to-end audio or phone performance verification. Local export uses isolated faiss-cpu 1.13.2 with existing NumPy 2.3.5; the remote audio evaluator's pinned environment is unchanged. FAISS is used only for development export/reference testing, not added to the app.

The first combined small-fixture test failed because the harness attempted rows 15 and 16 in an eight-row file. The harness was corrected to select only valid sample rows. The final combined run passed all 36 targeted portable tests, including wrong-hash, length, count, symlink, nonfinite, cancellation and cleanup rejection checks. All app Swift files passed syntax parsing. This is not an Apple SDK build.

## Additional held-out speech
Initially requested corpus offsets 3000/4000 returned no rows. Selected valid test-clean rows 2500/2600 before conversion or scoring. They are different speakers from prior fixtures and contain complete 5.455-second and 5.075-second utterances. Tested preselected retrieval strengths 0 and 0.125, with all other model, default native pitch and random inputs fixed.

| Fixture | Rate 0 ASR edits | Rate 0.125 ASR edits | Rate 0 target cosine | Rate 0.125 target cosine |
|---|---:|---:|---:|---:|
| 5683-32865-0017 | 1/15 | 1/15 | 0.9241 | 0.9162 |
| 121-127105-0022 | 0/16 | 0/16 | 0.9071 | 0.9172 |

The first converted utterance was recognized with "Link" instead of the reference name "Lake" at both rates. Its prepared input also had one ASR edit, but an insertion rather than that substitution. Automated recognition remains imperfect. On these 31 new reference words, retrieval did not change WER; speaker-score changes were mixed. The previous low-rate regression improvement therefore does not establish a consistent overall quality benefit. Defaults remain unchanged.

All four new full-duration outputs/chunks passed unchanged ONNX/PyTorch gates and independent reconstruction checks. Worst max absolute error was 0.00002885330468. Output sample counts were 218200 and 203000 at 40 kHz. No trimmed input, threshold relaxation or clipped PCM was admitted. Audio evaluation still uses the pinned CPU reference pipeline; it does not claim that the newly integrated disk backend generated these files.

## Provenance, reproduction and remaining work
LibriSpeech revision 71cacbfb7e2354c4226d01e70d77d5fca3d04ba1, CC BY 4.0, attributed to Panayotov, Chen, Povey and Khudanpur (2015), https://www.openslr.org/12. Original audio hashes, transcripts, native preparation hashes, model/index provenance and evaluator versions are retained in docs/qa/disk-index-broader. Existing VCTK licenses and all previous voice assets remain intact.

Probes under probes/rvc-candidates preserve pinned fixture preparation, conversion, evaluation, actual-index export and full-index comparison. The real-index probes run from the established workspace using the isolated rvc-index-reader-deps decoder, preserved native-retrieval-case.json and compiled /tmp/rvc-disk-vectors harness. The output directory is created fresh. Synthetic small-file rejection tests run with tests.test_rvc_disk_vectors; real full-bank evidence is separate.

Remaining: a verified large-pack import/manifest boundary and lifecycle integration in the phone workflow; Apple compilation; end-to-end native audio with the disk backend; measured physical-iPhone memory/latency and sustained use; broader speech and human listening/voice-likeness review. The uncalibrated speaker anchors may overlap model training data. No new IPA, model publication, Strata update, Mac runner or release claim was made.
