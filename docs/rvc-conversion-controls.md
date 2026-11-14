# Standalone conversion controls — 2026-11-14

The native file-conversion path now accepts retrieval strength 0–1 and pitch shift −24…24 semitones. UI controls default to the existing 0.75 / 0 settings, are disabled during active work, and are captured once per job and recorded in its live log. Every chunk uses the captured values.

At strength zero the pipeline skips index loading and neighbor search. Only the verified encoder and synthesizer packs are required. At nonzero strength, a missing retrieval index is rejected. Model admission hashes and existing voice storage are unchanged.

Validation: 4 new Swift-backed control tests passed; 6 existing feature-parity tests and 22 packaging tests passed. All app Swift sources passed syntax parsing. These changes have not been compiled against the Apple SDK, exercised on a physical iPhone, or used for a new audio-quality claim. No new IPA was published for this change.

Remaining blocker: the available project RVC checkpoints are synthetic smoke-test models plus generic training generator/discriminator weights. They are not validated production character models. The existing inference path remains diagnostic; broadening the manifest hash allowlist alone would not solve model quality or establish compatibility. Production voice assets, voice-quality acceptance, and physical-iPhone runtime/memory evaluation remain outstanding.

Subsequent external-model investigation found a VCTK p226 evaluation candidate. See rvc-vctk-p226-evaluation.md for integration, licensing and mixed quality results; it is not production-qualified.
