# Direct owned tensor buffers

The phone synthesizer now copies validated input arrays directly into the NSMutableData buffers retained for ORT inference. It no longer materializes a complete intermediate Data tensor dictionary first. HuBERT similarly copies its validated audio array directly into its owned mutable buffer. Raw pointers are callback-scoped; no borrowed pointer is stored or passed beyond its lifetime.

The synthesis intermediate payload is 5,026,764 bytes (4.79 MiB) per window; the HuBERT input intermediate is 590,720 bytes. This is a modest allocation reduction, not a solution for neural-model memory or an iPhone performance claim. Tensor names, shapes, element kinds and values, noise, models, defaults and voices are unchanged.

## Verification

A new test first failed because withTensorBytes did not exist. After implementation, all eight tests in test_rvc_native_synthesis, test_rvc_native_features and test_rvc_model_admission passed. Tests compare streaming bytes and shapes with the existing tensor encoder; check nonzero Float and Int64 values; mutate source arrays to verify owned-buffer independence; reject malformed inputs before invoking a consumer; and propagate consumer errors immediately.

Swift frontend parsing passed for the three changed files. Linux compilation executes the portable input encoder and Foundation buffers. The iOS ORT wrappers still require Apple SDK compilation and device verification.

Three isolated Linux processes per variant measured the small native preparation probe:

| Variant | Peak RSS KiB |
| --- | --- |
| Existing intermediate dictionary | 30,960 / 30,960 / 30,844 |
| Direct owned buffers | 25,288 / 25,644 / 25,272 |

The original-path probe explicitly keeps intermediate tensors alive while constructing owned buffers. These results measure the isolated allocation pattern without ORT or neural models and are not a whole-app RSS prediction. No claim is made that a production optimizer retains the original temporaries for the same duration.

See [raw measurements](qa/tensor-buffer-copy/result.json) and probes/rvc-candidates/RVCTensorMemoryChecks.swift. Compile the probe with VoiceMatrix/RVCSynthesisInputs.swift using Swift 6.1.3, then run legacy/direct in fresh processes and capture RUSAGE_CHILDREN high-water RSS separately for each run.

## Remaining work

Existing local speech fixtures examined in this step had already been evaluated; no new held-out quality result is claimed. Broader independent speech evaluation, listening/identity validation, phone runtime/memory and Apple compilation remain outstanding. No new IPA or model pack was published.
