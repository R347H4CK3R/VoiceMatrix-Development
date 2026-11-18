# Retained Clip Speaker Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax.

**Goal:** Review anonymous speaker turns in one authorized3–10s retained clip without creating voices.
**Architecture:** Thin analysis-only coordinator wraps existing pinned diarizer and receipt validation. Separate bounded sidecar stores immutable analysis identity and user aliases; SwiftUI exposes explicit analysis/review under audio lease and foreground/cancellation fences.
**Tech Stack:** Swift, SwiftUI, AVFoundation/CoreML, existing FluidAudio, Python native/fixture harness.
**Spec:** docs/superpowers/specs/2026-11-18-retained-clip-speaker-review.md

## Global Constraints
- Base exact2daf7bc843edc2a11cfa44eaa85cdd1d83923fe3; isolated feature/retained-clip-speaker-review.
- No automatic generation/reference/library/voice/train mutation; no release/feed/package changes.
- Source and receipts immutable; existing diarization3s minimum/overlap policy unchanged.
- Local aliases mean user labels, not model identity; bind to exact clip+analysis+speaker.

## Review Focus
- Corrupt or replaced clip/sidecar/receipt: fail closed and retain all originals.
- Cancellation/navigation/background racing completion: no stale publish, lease always released.
- Silence/overlap/short turns: no invented clean group or reference eligibility.
- Changed analysis/model/source: stale aliases cannot be applied.
- Multi-target source lists: native coordinator targets and app still compile.

## Tasks
- [ ] Write failing policy/store tests and native probe for bounds, exact evidence binding, aliases, symlinks/tamper, atomic durability and unchanged originals. Implement minimal separate ClipSpeakerReview store/coordinator files; use explicit file-size/entry bounds and source receipt validation.
- [ ] Write failing authorization/no-generation/lease/lifecycle tests. Add minimal retained-clip review UI and explicit action, without auto-start from navigation. Add labels and honest empty/overlap states. Update explicit target source lists only as needed.
- [ ] Prepare deterministic bounded licensed speech fixtures from existing pinned recordings: silence, one speaker, alternating two speakers and overlap. Do not fabricate identity acceptance or assume short-clip clustering quality; actual result determines honest UI outcome.
- [ ] Add native real diarizer/handoff/preservation checks and simulator UX fixtures. Run local regressions; separately report native unavailable on Linux.
- [ ] Independently review diff, then push only feature branch and require actual native app compile, inference, UI tests. No packaging/publication in this slice.
