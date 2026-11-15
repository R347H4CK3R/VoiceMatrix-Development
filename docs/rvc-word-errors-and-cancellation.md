# Remaining word-error diagnosis and model-load cancellation

## Fixed-audio decoding comparison

The preserved two-speaker regression WAVs were evaluated again with the same hash-verified Whisper model, changing only greedy decoding to a preselected three-beam search. Six audio files (source, retrieval off, 12.5% retrieval for each speaker) were hash-checked against the prior report. No voice audio was regenerated or modified, and the greedy results remain the primary baseline.

Every normalized word-error count remained unchanged:
- 2961-960-0003: 0/39 for source and both conversions.
- 4507-16021-0031: 3/34 for source and both conversions.

For 4507, converted ASR substitutions at reference word indices 21, 31 and 32 are a→their, choice→choices and is→are. Source ASR also substitutes a→their and choice→choices, but deletes is. Exact dynamic-programming alignments are preserved for both decoding methods, and alignment operation counts were checked against the independently computed edit totals.

This rejects the narrow hypothesis that a three-beam decode fixes these errors. It does not establish that the underlying speech is correct, that the voice sounds natural, or that recognition errors prove a conversion defect. A stronger independent evaluator or human listening is needed to resolve the remaining phonetic ambiguity. No quality threshold or application default was changed.

The prior cases were held out before their initial scoring; after that evaluation they are regression cases, not new hold-outs. No additional speaker-similarity scoring was claimed in this step.

Evidence: [result.json](qa/decoder-sensitivity/result.json). Reproduction: probes/rvc-candidates/evaluate_decoder_sensitivity.py in the existing isolated evaluation runtime, with the same pinned evaluator model cache and source/converted WAVs. It disables network inference, rejects an existing output report, uses a fixed 128-token ceiling, and checks that no decoded sequence reaches that ceiling. No new model downloads or dependencies were introduced.

## Phone resource handling

The Swift model wrappers now check cancellation immediately before beginning ORT environment/session setup and immediately after synchronous session construction returns. Both checks are inside the existing cleanup catch, so cancellation removes the verified model snapshot and releases the newly constructed local session. The window converter also checks cancellation between encoder initialization and synthesizer initialization, inside the catch that closes the encoder.

This prevents a cancelled job from advancing to another expensive model load at those boundaries. It cannot interrupt a synchronous ORT constructor already running; cancellation is observed when that call returns. Existing success/failure cleanup, voice assets, model pins and processing bounds are unchanged.

Verification: Swift frontend parsing passed for RVCONNXHuBERT.swift, RVCONNXSynthesizer.swift and RVCNativePreparation.swift. The affected paths are iOS-only and were not compiled against the Apple SDK or executed on a phone. This step makes no measured phone memory/latency claim. The six real-audio decoder runs completed successfully in the existing Windows CPU runtime; Linux was used for source edits, parsing and evidence checks.

Human listening, actual iPhone behavior and production voice qualification remain unverified. No new preview, IPA, source feed or model pack was published.
