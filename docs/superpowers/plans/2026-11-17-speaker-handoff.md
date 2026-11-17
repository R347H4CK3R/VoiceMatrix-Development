# Exact Saved-Speaker Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Open speech or conversion for the explicitly chosen saved speaker, never a stale library selection.
**Architecture:** A pure identity matcher rejects missing/duplicate/hash-mismatched profiles. LocalVideoStudio gates the explicit action by job and activity, reuses retained asset validation, then sets selectedID. SwiftUI navigates only on success.
**Tech Stack:** Swift/Foundation/SwiftUI, existing local engines, Python unittest, native XCTest.
**Spec:** docs/superpowers/specs/2026-11-17-speaker-handoff-design.md

## Global Constraints
- Preserve every retained file and existing selection on failure.
- No synthesis/conversion/network starts in the selection action.
- No release or version edits in this local-only task.

## Review Focus
- Stale history job: no selection.
- Busy/inactive/audio lease: no selection.
- Duplicate or changed profile: no selection.
- Missing/tampered retained receipt: no selection.
- Successful distinct speaker: correct ID and explicit destination mode, no automatic generation.

### Task 1: Bound handoff and navigation
- [ ] Write native Foundation matcher cases and source wiring tests; observe missing-feature failure.
- [ ] Add LocalSpeakerHandoff identity matcher, LocalVideoStudio.selectSpeaker(jobID:speaker:library:audio:) -> Bool, and per-speaker navigation.
- [ ] Add native XCTest for distinct speakers, stale IDs, activity/lease guards and changed files/profile without data mutation.
- [ ] Run focused tests, full project suite and Swift syntax check. Report native execution remains pending.
- [ ] Independent review before any source upload; no commit or publication until parent decides next release scope.
