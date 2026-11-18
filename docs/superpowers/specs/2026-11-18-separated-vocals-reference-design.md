# Separated vocals to speaker-reference studio

Explicit action on a retained separation result opens the existing Video Voice Studio with vocals preselected, without Files export/reimport. It does not start generation or enable authorization. Speech, overlap, sound-screening, word-check and preview gates remain unchanged. Separation is neither identity verification nor training and may leave music/artifacts or remove speech information.

Chosen approach: a bounded, exclusively created private WAV snapshot carrying its receipt-bound SHA256 and byte count. Fresh store listing and exact receipt equality reject changed/stale pairs. Snapshot creation checks the expected vocal digest, then the downstream source copy checks the expected count/digest before committing sourceFile. This protects against changes while the user considers authorization. Existing source/stems are never modified/deleted.

Alternatives: raw URL prefill is smaller but unbound during delayed processing; Files export/reimport keeps the current friction and loses provenance. A new generation pipeline would duplicate safety gates and is excluded.

Limits: existing 64-entry store bound, 10-second canonical stereo WAV; no new model, network action, automatic generation, publication, or quality claim. Completed snapshots use a deterministic result UUID + expected digest filename and are freshly validated before reuse, including at the admission limit. New snapshots use private staging and exclusive atomic promotion; corrupt existing snapshots are rejected without overwrite. Completed snapshots remain retained; incomplete newly owned staging files may be removed. Native compile/store tests and UI interaction remain required before delivery.
