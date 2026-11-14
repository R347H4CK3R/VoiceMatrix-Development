# User-assigned character names

Unknown speakers can now be given a name after listening: open Choose a voice, expand Voice details, and choose Name this voice. Saved names appear in the picker and selected-voice screens and can be searched. Original source names remain visible and searchable. Use original source name resets the label.

Names are private, separate records bound to the stable voice ID and exact reference SHA-256. They never alter the original collection, audio, permissions, transcripts, reference hashes or listening reviews. A changed reference does not inherit a previous label. Reset writes an empty label record, rather than deleting any voice files. Damaged records fail closed and are preserved.

This is manual identification by the listener, not automatic character recognition, verified identity or guaranteed likeness. It does not add music separation or RVC training.

Host verification compiles the actual Foundation store and extracted production library methods. Tests cover persistence, restart, changed-reference invalidation, invalid input, damaged-record preservation, busy-state rejection, UI-source wiring and reset. Swift syntax parsing passes. A native UI test for naming, relaunch and reset is authored but has not run here; actual Apple SDK build and iPhone UI checks remain required.
