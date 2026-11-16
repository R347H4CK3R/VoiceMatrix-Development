# Reference recognition context candidate

Newly extracted Video Voice Studio references use a fixed 250 ms leading silence buffer only for local speech recognition. The reference audio is not edited, trimmed, overwritten or padded for synthesis. Existing imported profiles and transcripts are not silently changed. Generated-preview and catalog-output recognition retain the prior `transcribe` path and acceptance thresholds.

The receipt binds the original input SHA-256, recognized transcript SHA-256 and actual leading-frame duration. Older receipts without this optional field still decode. The bounded reference path never adds a second recovery pad; input plus context must fit the existing 30-second ASR limit. Models remain lazy-loaded and released, with existing cancellation and deadline checks.

## Evidence before product integration

- Diagnostic 43810755144 reproduced a missing initial word on one exact retained human reference; predeclared zero-silence context variants recovered it without text prompts. Two neutral controls were unchanged.
- Independent human holdout 43812273447 used four new complete licensed recordings; all eight original/context outputs had zero corpus-word errors. This is a small cohort, not general accuracy proof.
- Experimental full route 43812520803 imported both distinct reference intervals, preserved existing profiles/source, resumed and reloaded, and generated new speech with zero word errors for both. A separate original/unpadded recognizer also checked both final waveform hashes and reported zero word errors.

Those experiments altered diagnostic recognition context broadly, so they are NOT proof of this narrower product integration. The candidate must pass its own reference-only full-route receipt checks, four-human production-API checks, native PCM/cancellation/legacy-receipt checks, simulator suite and inspected IPA gates before publication. Original build 10 remains the fallback.

This remains an unfinished 0.4.9 preview, not completed 1.0.0. Physical iPhone behavior, character identity and perceptual likeness are unverified; music separation, reliable overlapping-speaker extraction and full RVC training remain incomplete.
