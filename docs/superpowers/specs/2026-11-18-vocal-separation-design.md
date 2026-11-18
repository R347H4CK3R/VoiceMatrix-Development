# Bounded standalone vocal separation

## Goal and delegated choice
The user wants fully on-iPhone media processing including music removal, speaker work and RVC, with no laptop dependency. This increment implements actual vocal/accompaniment separation for an entire authorized local clip of at most 10 seconds. The engineering choice is delegated; this is not an assertion that the user selected a particular model.

## Approaches
- Spleeter two-stem float32 ONNX: selected. Explicit source and weight MIT provenance, existing ONNX Runtime, two approximately39MB models, independently reproducible transform contract.
- Demucs Core ML: promising but larger activation/memory and conversion provenance burden. Not selected for the bounded first increment.
- Automatic character identity or on-device RVC training: not interchangeable with separation. Neither is claimed by this increment.

## Boundaries
44100Hz stereo, up to10seconds, bounded64MiB import, preserve original and completed outputs. Never silently trim. Explicit import and run; no background download, upload, laptop, queue mutation or automatic reference acceptance. Real pinned model inference only. Vocals and accompaniment can be listened to and exported independently. Experimental quality and physical-device performance remain unverified until tested.

## Model and transform contract
Spleeter two U-nets exported by k2-fsa/sherpa-onnx. Archive SHA256 e26401d9c1801f43c0229731d78d32c2e80085e3aceedeb25f29d2de5fa68ca2,74682545bytes. Vocals bdc16ab6bf6117ddd4842c19e80e40e2be188fc555295064d424616b0224ac97,39318336bytes. Accompaniment671ace17acd3720674a2bc14de32ac6292453dec20d9eb0ba4255d4ad8e3d8c0,39318343bytes.
Input/output float32[2,1,512,1024].44100Hz is established by both upstream Python and C++ preprocessing; exported metadata41000 is erroneous and must not control resampling. FFT4096,hop1024,periodicHann,uncentered. Retain1024bins,512framepadding, squared-magnitude two-model masks and originalphase; higherbins zero according to reference. Explicit4096sample zero guards and tailhop alignment then exact crop preserve input boundaries. This wrapper policy must be applied identically in parity references, not conflated with untouched upstream preprocessing.

## Safety and validation
Pinned model validation, finite tensor/sample checks, explicit memory bounds, cancellation between bounded stages. Hold processing lease until synchronous inference exits. Commit both stems atomically; never expose a half pair. Failures retain original and earlier results. Tests must include genuine native/reference parity, short/silent/boundary signals, exact length, corrupt model, cancellation and publication interruption. Tests do not prove perceptual quality or speaker identity.

## Core inference contract and verification evidence
The implementation uses original float32 Spleeter ONNX models (opset13) with the already vendored ONNXRuntime1.24.2 CPU engine, two threads and no CoreML execution provider. Both graph hashes and bytecounts are compiled into `VocalSeparationAssets`; manifest edits cannot authorize a model. Sessions use private bounded hash-verified copies and delete only those copies on close.

Frames:1...441000 perchannel at44100Hz, finite normalized floats. Add4096zero samples at bothends, ceil finalhop1024, FFT4096 periodicHann/unnormalized, magnitudes first1024bins, zero framepad to512. Actual two U-net outputs become squared softmasks with total1e-10epsilon, retain originalcomplexphase, highbins zero, inverseFFT/N, squared-window overlapnormalization, crop exactinputframecount. Frequencies above about11kHz are intentionallyremoved; no fullband claim.

Published model metadata incorrectly says41000; both exporterreferencePython and C++ runtime hardcode44100. The immutablepack keeps modelbytes unchanged and explicitly pins44100 in source and manifest. Upstream sherpa source pin:a8cd5f3bc9490a9a58aa319cf0d5b60b6cd9e642.

License provenance: Deezer authors explicitly license code and pretrained models MIT in https://doi.org/10.21105/joss.02154 (page3). Deezer copyright/license is retained in LICENSES/Spleeter-MIT.txt and stagedpack. Conversion sources are Apache2 from k2-fsa/sherpa-onnx; no upstream executables are run. Models are from its published source-separation-models release and match its checksum.txt.

Initial actual PythonORT1.24.2 evaluation uses fixed first4seconds of repositorylicensed4507-16021-0031 FLAC plus deterministic generated accompaniment. Vocal-left error to knownspeech is0.00025987049MSE versus0.0040364233MSE for the mixture. This is a speech-plus-instrumental surrogate, not a singingbenchmark or phonequalityclaim. Native simulator gate compares all4stems to independent NumPyFFT+ORT reference, maxerror<0.002 and RMSerror<0.0002; fixed knownmixture error must improve by at least20%. Nativegate has not yet run.
