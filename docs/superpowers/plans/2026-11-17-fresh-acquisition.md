# Fresh Acquisition Implementation Plan

> For agentic workers: execute task-by-task with test-first changes.

**Goal:** Give failed, retained URL jobs a safe explicit fresh-acquisition path.
**Architecture:** Foundation-only URL provenance helper; controller guards current job identity and delegates to existing new-job creation; SwiftUI confirmation explains retained files and network request.
**Tech Stack:** Swift 6, SwiftUI, Python unittest source checks and executable Swift policy checks.
**Spec:** ../specs/2026-11-17-fresh-acquisition-design.md

## Global Constraints
Preserve all retained jobs/files. No automatic retries, bypasses, external services, release changes or universal-download claims.

## Review Focus
Reject mismatched original/source URL, direct stream substitution, stale confirmation, completed/source-retained jobs and unauthorized retry.

## Task
- [ ] Add failing source wiring checks and executable Swift provenance cases.
- [ ] Implement URL provenance helper, identity-bound controller action and confirmation UI.
- [ ] Run focused and full regression suites; report native UIKit tests as unrun unless actually executed.
- [ ] Independent review before any CI/source upload; versioned release remains separate.
