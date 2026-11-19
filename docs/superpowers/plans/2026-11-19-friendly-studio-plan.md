# Verification and delivery plan

1. Isolate exact verified manual-turn UI baseline on feature/friendly-voice-studio.
2. Source regression tests first: hero and steps, collapsed details, unchanged controls and permission gates, Dynamic Type and touch target structure. Confirm red, then green.
3. Change only App.swift and LocalVideoStudioView.swift presentation; no business logic or persistence edits.
4. Update native log test to explicitly expand the new collapsed details, retaining original content checks. Add largest accessibility text case with permission off, 44pt chooser, navigable controls and screenshot.
5. Run full portable discovery, classify missing native/tool requirements separately. Preserve all failures in report.
6. Before merge, run character-ui-smoke on exact patch SHA plus retained-clip-speaker-review-ui seeded manual-turn regression. Inspect normal and largest-text screenshots, permission/paste, repeat Back/reopen, empty library, retained history and review/label routes. Verify VoiceOver labels manually or accessibility audit and reduced-motion no new animation.
7. No package/release/merge. Source checks alone do not establish rendered contrast/layout or native interaction success.
