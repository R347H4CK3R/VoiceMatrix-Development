# Resume validates saved speaker receipts

Resume previously counted a catalog ID plus the current quality-policy marker as a saved speaker, even if its retained reference or preview had gone missing or changed. This could allow a resumed partial job to appear complete without usable preview evidence.

Resume now uses the same bounded, paired-file receipt validator as explicit playback, and requires the saved reference hash to match the catalog profile. Missing receipts, different profile hashes, missing/changed files, symlinks and invalid filename pairing cannot take the already-saved shortcut. Processing proceeds through the existing candidate/reverification path; sources and existing catalog voices remain intact. Playback remains disabled during processing.

Verification: focused Python wiring checks plus a Linux Swift harness executing the production validator against temporary files (intact, missing, changed, symlinked, wrong voice/pair and repaired), with an explicitly substituted deterministic hash boundary. The harness does not test CryptoKit, AVFoundation, synthesis, SwiftUI or iPhone execution. Existing completion persistence regression also passes. Native build and actual media-to-speech/device verification remain release blockers.
