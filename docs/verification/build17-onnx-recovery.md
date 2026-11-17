# Build17 ONNX dependency acquisition recovery

The prior source pins microsoft/onnxruntime-swift-package-manager at
b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2. On November 17, exact-source
reruns could no longer fetch that public repository. The resulting dependency
resolution error happened before compilation/tests. It does not establish that
the prior adaptive-merge test failure was fixed.

This isolated candidate uses Microsoft's official ONNX Runtime 1.24.2 pod
wrappers without source edits, and the same 1.24.2 binary archive identified by
the former pinned Package.swift. It does **not** claim that pod wrapper bytes
are identical to the inaccessible SPM commit. Native ABI/API and behavioral
compatibility still require all unchanged relevant gates on this new source.

Source archive:
https://download.onnxruntime.ai/pod-archive-onnxruntime-objc-1.24.2.zip
SHA-256: ab102b30f15c44b08dc6fc32683abeafd216ff6bcabdf74fbac37fbb19d80eed

Binary archive:
https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip
SHA-256: f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54
This hash matches the former pinned package manifest. Inspected slices include
iOS arm64, iOS simulator arm64/x86_64 and macOS arm64/x86_64.

The local Package.swift recreates the consumed OnnxRuntimeBindings product,
SPM_BUILD define and C++17 setting. The unused extension product is not added.
The complete official wrapper archive contents and MIT license are preserved.
A hash-pinned inventory rejects additions, omissions, symlinks and changes.
Release evidence includes this inventory and license and binds the dependency
into the inference source fingerprint. Existing release assets, catalogs,
private recordings and runtime acceptance thresholds are not changed.

This branch is a repair candidate, not a release. Native verification remains
mandatory; local Python passes are not native compile or iPhone evidence.
