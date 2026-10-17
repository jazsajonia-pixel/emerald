# Phase status

| Phase | Status | Notes |
| --- | --- | --- |
| 0 — Repository and build foundation | Done | CI green, APK artifact uploaded (PR #1) |
| 1 — Shell and navigation | Done | Widget-tested (PR #2); launch verified on emulator from Phase 2 CI |
| 2 — Safe Markdown vault access | Done (CI + emulator) | PR #3. Real-folder picker flow still needs the manual device checklist |
| 3 — Links, backlinks, search | Done (CI + emulator launch) | PR #4. In-memory index instead of SQLite (see docs/LINKS_AND_SEARCH.md) |
| 4 — Interactive graph | Done (CI + emulator launch) | PR #5. Custom force layout, global/local, highlight, filters |
| 5 — AI foundation and safe tools | Done (CI + emulator launch) | PR #6. Gemini adapter, vault-scoped tools, approval flow (docs/AI.md). Real API not exercised (mocked) |
| 6 — Additional providers / agents | Done (CI + emulator launch) | PR #7. OpenAI-compatible adapter (OpenAI, local Ollama); MCP not implemented (documented decision). Real APIs not exercised (mocked) |
| 7 — Backup and hybrid sync | Done (CI + emulator launch) | PR #8. GitHub repository sync chosen by the owner (docs/SYNC.md). Fake-API tests plus a real GitHub API check on a temporary branch (in-memory vault, not a phone) |
| 8 — Release hardening | In progress | Expanded emulator tests, optional stable signing via secrets, versionCode from CI run, docs/RELEASE.md. Real-device checklist not yet run |

Testing levels are reported separately: unit/widget tests (CI), CI APK build,
emulator tests, and real-device tests. A phase is not marked "Done" for
behavior that was only compiled.

## Verification summary (October 2026)

| Level | Status |
| --- | --- |
| Unit + widget tests | Run in CI on every PR (205+ tests) |
| Release APK build | Built in CI on every PR; artifact `emerald-android-apk` |
| Emulator (API 34) | Launch, navigation, real SAF channel restore, core note flows with an in-memory vault, Keystore secure storage, app-private files |
| Real AI providers | Not called (no keys, no paid usage); mocked against official request/response shapes |
| Real GitHub API | Sync client and engine checked on a temporary branch (deleted afterwards) |
| Real phone | **Not done.** Run the checklist in docs/TESTING.md and record results here |

## Known gaps

- Choosing a real folder with the system picker and reading/writing real
  files via SAF has only been exercised by code paths shared with the
  emulator test, not by a full on-device flow.
- APKs are debug-signed until a release keystore is configured
  (docs/RELEASE.md); upgrades between CI builds may need an uninstall.
- AI-inferred graph links are not implemented (edge kind reserved).
- No streaming AI replies; no background sync.
- License not chosen yet (LICENSE_DECISION.md).
