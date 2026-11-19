# Original NVIDIA model frontend buffers

Source: NVIDIA parakeet-tdt-0.6b-v3, immutable revision541d1f99c6b0c3cd0b11a95167540bb8edefd82b.
https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/tree/541d1f99c6b0c3cd0b11a95167540bb8edefd82b
Original model designated CC-BY-4.0: https://creativecommons.org/licenses/by/4.0/
Credit: NVIDIA. Original full checkpoint digest and individual raw buffer digests are recorded in provenance.json.
Modification: selected two original Float32 buffers from the original checkpoint and serialized their unchanged raw little-endian bytes as separate files; no trained weights changed. model_config.yaml is an unchanged selected original archive member, SHA256eadae985ef97451402be2faef3b240c2cae7d9cc0362c5bd00e64dfc4265ed09.
The Apache2 license accompanying the independent tooling does NOT replace the original model's CC-BY4 terms. This package does not contain FluidInference's converted preprocessor. No native inference/export parity has been established.
