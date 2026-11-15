# Full-window native retrieval and synthesis parity

Two existing LibriSpeech regression fixtures passed the production Swift pack loader, full disk-backed retrieval, and native feature/pitch preparation feeding the pinned CPU PyTorch synthesizer. This extends the prior three-row retrieval check to 922 genuine encoder rows and 7,376 neighbor selections. It does not change application defaults or qualify a production voice.

| Fixture | Neighbor differences | Audio max absolute error | Audio RMS error | Native process peak RSS |
| --- | ---: | ---: | ---: | ---: |
| 5683-32865-0017 | 0 / 3,688 | 4.70318e-6 | 8.67054e-8 | 50,476 KiB |
| 121-127105-0022 | 0 / 3,688 | 3.75509e-6 | 5.06303e-8 | 50,556 KiB |

Both coarse and continuous pitch matched exactly. Feature maximum error was 2.38419e-7. The explicit-noise synthesizer adapter matched the original inference call exactly. Native preparation took 1.754 and 1.693 seconds; hash-verified loading took 0.484 and 0.625 seconds on this Linux host. Output duration was preserved at 218,200 and 203,000 samples at 40 kHz.

## Scope and unchanged gates

Retrieval rate was 0.125, protect 0.33, nprobe 1, eight neighbors, complete pinned 45,313-vector index. HuBERT features came from actual speech and the pinned cached encoder. Original and native-input synthesis used the same captured random draws (seed 347). Exact neighbor IDs/coarse pitch, feature allclose rtol=3e-5/atol=2e-6, adapter max/RMS 1e-6/1e-7, and generated audio max/RMS 2e-4/2e-5 were selected before execution and retained.

RSS is Linux resource.getrusage(RUSAGE_CHILDREN) for a fresh wrapper around one native harness process (including its SHA subprocess). It excludes HuBERT and synthesis, includes a second search used only to compare neighbors, and cannot establish whole-app or iPhone memory use. The encoder was run in a separate completed process.

These are regression fixtures previously evaluated for intelligibility, not new held-out samples. Numerical parity is not a new listening, transcript, speaker-identity, or production-quality qualification. Apple SDK compilation of the latest import wiring, physical iPhone runtime/memory, and human listening remain unverified. Build 6 predates the latest import wiring. No IPA, feed, model pack, or default was published or changed in this step.

## Reproduction and provenance

The evidence JSON records original corpus revision, CC-BY-4.0 attribution/source links, input and output hashes, verified model/source hashes, timing, RSS, and per-case gates. Original WAVs remain in the local evaluation workspace; model/audio binaries are not added to source.

The archived Python probes retain the evaluation workspace layout and are not a dependency installer. Run from that workspace using pinned NumPy 1.26.4, FAISS 1.13.2 and PyTorch 2.6.0+cpu in voicematrix-hubert-deps. Required cached inputs are described by the script paths and evidence; do not replace missing pinned assets with unverified files. The encoder creates fresh case directories; the comparison creates native subdirectories and refuses existing ones. Preserve evidence before a rerun.

Compile RVCFullWindowChecks.swift with the production RVCDiskVectorBank, RVCNativeRetrieval, RVCRetrievalAssets, RVCNativePreparation, RVCFeaturePreparation and synthesis input definitions using Swift 6.1.3 on Linux; the probe expects /tmp/rvc-full-window-checks. Run encode_native_full_windows.py, then compare_native_full_windows.py. Both inference probes disable network connections. Python scripts use assertions as test gates and must run without optimization (-B is fine; -O is not).

Related integration evidence: [pinned retrieval import](rvc-pinned-retrieval-import.md).
