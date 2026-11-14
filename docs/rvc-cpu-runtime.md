# CPU RVC synthesizer runtime

This is an executable inference component, not a complete voice-conversion app. `tools/rvc_onnx_runtime.py` accepts the existing fixed 100-frame ONNX exporter contract and returns a new 40,000-sample waveform tensor. It requires all eight explicit inputs, including pitch, HuBERT features and recorded noise. It does not derive these inputs from audio.

## Verified result

On 2026-11-14 the reusable runtime executed the existing synthetic diagnostic RVC model on GeForce's CPU using an isolated, user-approved Python 3.12.10 installation. All five exported cases passed against original PyTorch waveform references. Maximum absolute error was 4.839897155761719e-05; maximum RMS error was 7.658118418156749e-06. Limits are 2e-4 absolute and 2e-5 RMS. The machine-readable report is in `docs/qa/rvc-cpu-runtime-reference.json`. No original model, index, fixture or voice pack was changed or uploaded. No voice identity or likeness is verified.

The model's provenance remains the original synthetic speech diagnostic described in `docs/qa/rvc-corrected-synthetic-smoke.json`, using upstream RVC revision 81eed5e8f68b6bed1789f682fe78cdd324495afc (MIT; see LICENSES/RVC-MIT.txt). Model SHA-256: 1d7dd41135f8cf4e88c0f186298b6e2d2b599e553acdec3fcd82737eb00dd0bf. The runtime contains no model weights or automatic model downloads. NumPy is BSD-3-Clause, ONNX Apache-2.0, and ONNX Runtime MIT; installed package metadata carries their notices. These Python dependencies are not bundled in the iPhone app.

## Use and tests

Use a separate Python 3.12 environment, then install `pip install -r tools/rvc-runtime-requirements.txt`. Run `python -m unittest tests.test_rvc_onnx_runtime -v`. All eight runtime tests must execute; ordinary source discovery explicitly skips them if the optional ONNX dependencies are absent. The tests use a labeled non-neural contract graph; only the separate recorded GeForce run is real RVC synthesizer evidence.

Construct `RVCSynthesizer(model_path, verified_sha256)`, call `run(tensors)`, and close the session when finished. `run_export_case(runtime, export_folder, case_name, verified_manifest_sha256)` reads the exporter child-result.json, validates the model association, verifies tensor metadata and exact bytes, runs inference, and compares with the original reference. The caller must obtain trusted model and manifest hashes independently. A caller-controlled hash is not a sandbox for untrusted models.

The reader bounds file sizes and rejects special files and symlinks. Inputs have exact shapes/dtypes and finite-value checks. The CPU session uses two intra-op threads, one inter-op thread, and serializes calls. Cancellation is checked before and after inference, not during an ONNX Runtime call. Fixture comparisons return an explicit failure boolean when outside tolerance. Output is a tensor; no audio is automatically published.

## Remaining integration

This does not implement HuBERT extraction, pitch extraction, indexed neighbor search, resampling/context/padding DSP, long-audio chunking or iOS ONNX execution. The Swift feature-preparation component is tested separately and is not yet connected to this Python runtime. The synthesizer only accepts 100 frames; the full pipeline's context can require about 298 frames even for short input. Do not advertise this component as full offline RVC, native-phone verification or a finished 1.0.0.
