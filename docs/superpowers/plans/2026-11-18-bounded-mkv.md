# Bounded MKV Implementation Plan

> For agentic workers: use subagent-driven implementation and independent review.

**Goal:** Genuine optional MKV with preserved original compressed packets.
**Architecture:** Bounded Swift MP4 tables feed streaming MatroskaWriter; MP4 remains the decoder companion.
**Tech Stack:** Foundation Swift, existing MatroskaWriter; no new dependencies.
**Spec:** docs/superpowers/specs/2026-11-18-bounded-mkv-design.md

## Global constraints
Preserve sources, queues, prior releases and parity gates. Explicit unsupported fallback. Limits from spec apply to parser, mux and tests.

## Review focus
Truncated/overflowing tables; external/symlink/mutating sources; unsupported edits/reordering; partial output/cancellation; metadata-versus-packet timing inconsistencies.

## Tasks
- [ ] Implement MP4SampleTable with bounded metadata reads and sample ranges, byte-exact read and identity verification. Reject unsupported edits/fragmentation/encryption/refs/counts/offsets.
- [ ] Replace AVAssetReader export loop with merge of original track sample timelines. Keep storage, work, cancellation and temporary-output policy.
- [ ] Independently generate malformed MP4 inputs and test rejection/preservation through actual native exporter.
- [ ] Run unchanged native decoded parity plus independent packet/timing checks. Add parser to diagnostic target and native test compiler list.
- [ ] Review exact source and run app, resolver, UI, aggregate and standalone pipeline gates. Do not publish or package as verified until required checks pass.
