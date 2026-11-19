# Friendly VoiceMatrix studio

Chris delegated design choices and asked for an eye-catching UI readable by ages 13+.
This is a readability target, not an age-policy change. Base: 5ad43aa0aa89a4b3484d6df371ac5b3d2f05c3bb.

Choose a focused SwiftUI presentation refresh, not a new wizard or navigation replacement:
- Electric purple hero and teal numbered steps on dark high-contrast surfaces.
- Primary Home entry: Make a voice from video. Other routes remain in place.
- Add video → Pick clips → Try voice is guidance, not fabricated job progress.
- File selection and explicit paste precede jargon; permission remains opt-in.
- Technical explanations and logs collapse without deleting history or hiding current status.
- Existing callbacks, authorization checks, confirmations, receipt semantics, IDs and persistence remain unchanged.
- Dynamic Type uses semantic fonts and horizontal-to-vertical step layout. No animations added, so reduced-motion settings incur no new motion.
- Existing route still truthfully identifies MP4 companion analysis; no strict MKV claims.

Tradeoffs: a full wizard could reduce visible actions, but would alter navigation/state and risk ongoing work. Colors-only would not fix dense instructions. Focused presentation is the smallest useful change and independent of the pipeline branch.

No packaging, release, merge, identity recognition or new voice-quality guarantees.
