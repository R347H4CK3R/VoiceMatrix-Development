# Resident neural-model memory check

The pinned CPU HuBERT encoder and VCTK p226 PyTorch synthesizer were retained together for two passes over two existing LibriSpeech regression cases. All four outputs exactly matched the prior native-preparation WAV SHA-256 hashes. Network inference was disabled and original assets were preserved.

Parent-process sampled peak RSS was **2,341,340 KiB (2.233 GiB)**. The Linux lifetime high-water reading was 2,340,840 KiB. Encoder loading peaked at 1,368,924 KiB; synthesis was the highest sampled stage. The second pass did not exceed the first-pass peak, but four windows cannot establish long-duration stability or leak freedom.

This is a CPU evaluation process, including Python libraries, PyTorch allocations, a retained checkpoint, both neural models and inference intermediates. It is not the iPhone application or its ONNX Runtime backend. The previous approximately 49.4 MiB native retrieval/preparation measurement excludes these models and must not be presented as whole-pipeline memory.

## Coverage correction

The 20 ms sampler observed parent RSS but recorded zero child RSS throughout native execution. Therefore combined-process RSS was **not established**. The corrected evidence reports parent-only memory and preserves the original report hash. Sampling can miss short peaks; Linux RSS accounting and the resource high-water reading can differ. Memory remained about 2.06 GiB immediately after model references were closed; this includes retained allocator/library state and does not by itself prove a leak.

## Phone wiring review

Source inspection found the Studio worker closes its converter after success and on thrown errors. Cancellation propagates to that worker. Converter close releases the disk-backed retrieval index and closes both ORT actors; each actor releases its session/environment and removes its model snapshot. Model-loading failure closes the already-open encoder. These are source observations, not Apple compilation or device verification, and no production behavior was changed in this step.

## Evidence and reproduction

See [result.json](qa/resident-model-memory/result.json) and probes/rvc-candidates/measure_resident_memory.py. The probe uses the same pinned assets, source closure, noise and workspace layout as [full-window parity](rvc-native-full-window.md). It requires a fresh rvc-resident-memory-20261115 directory, the compiled native helper and the prior feature/noise fixtures. Assertions are test gates; run without Python optimization.

No new held-out quality claim follows from repeated regression output equality. Broader independent speech tests, human listening, physical-iPhone performance/memory, and Apple compilation of the latest import wiring remain outstanding. No IPA, source feed, model pack, or defaults were published or changed.
