# Unicode diagnostic retention

The standalone studio persists every activity event before committing its status. Its previous 2,000-character text bound did not bound UTF-8 bytes: emoji in both event fields exceeded the 8 KiB encoded-entry limit. A single grapheme containing many combining marks also bypassed the intended bound. Such an event rejected the durable update and could stop the workflow.

Diagnostic text now keeps at most 2,000 UTF-8 bytes per field, ending at a complete Unicode scalar. The bound applies before regular-expression redaction and again afterward, since replacement markers can expand text. Control filtering and credential/path redaction remain active. Existing journal files and voice packs are neither rewritten nor deleted. This changes retained diagnostic text, not voice names, transcripts, models or audio.

The regression failed against the previous implementation with `Unicode diagnostics exceed the journal entry budget`. It now encodes, appends and reads real Foundation journal entries containing emoji, a large combining-mark sequence, and JSON-escaped punctuation/newlines without invalid UTF-8. The existing redaction, pagination, legacy recovery, FIFO/symlink and damage-preservation checks still pass.

Candidate starts from private commit d9cb393fdce7d838190b45ea92e5b608aacf4a52. Only LocalStudioJournal.swift, its Foundation checks and this document change. The focused studio gate passed 36 tests with zero skips; the Foundation policy gate passed 6 tests with zero skips; all 58 app Swift files passed syntax parsing. These are Linux results, not Apple SDK typechecking or native-device verification.

No release, new IPA, Strata update, real neural inference, character-likeness result or completed 1.0.0 is claimed. On-device RVC training/conversion, reliable music separation and the previously documented device/audio verification gaps remain unresolved.

Full candidate discovery: 746 tests, 742 passed, 4 platform skips, zero failures/errors (251.725 seconds). Skips are the three Windows-specific tests and the Apple CryptoKit contract. The first suite invocation used the parent directory and failed imports/subprocess paths; it is superseded by this complete run from the repository root.
