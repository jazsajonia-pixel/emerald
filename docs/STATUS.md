# Phase status

| Phase | Status | Notes |
| --- | --- | --- |
| 0 — Repository and build foundation | Done | CI green, APK artifact uploaded (PR #1) |
| 1 — Shell and navigation | Done | Widget-tested (PR #2); launch verified on emulator from Phase 2 CI |
| 2 — Safe Markdown vault access | Done (CI + emulator) | PR #3. Real-folder picker flow still needs the manual device checklist |
| 3 — Links, backlinks, search | Done (CI + emulator launch) | PR #4. In-memory index instead of SQLite (see docs/LINKS_AND_SEARCH.md) |
| 4 — Interactive graph | In progress | Custom force layout, global/local, highlight, filters |
| 5 — AI foundation and safe tools | Not started | |
| 6 — Additional providers / agents | Not started | |
| 7 — Backup and hybrid sync | Not started | |
| 8 — Release hardening | Not started | |

Testing levels are reported separately: unit/widget tests (CI), CI APK build,
emulator tests, and real-device tests. A phase is not marked "Done" for
behavior that was only compiled.
