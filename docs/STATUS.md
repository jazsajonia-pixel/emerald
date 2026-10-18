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
| 8 — Release hardening | Done for CI + emulator; real-device check pending | PR #9. Emulator flow tests (4/4 pass), optional stable signing via secrets, signer reported in CI summary, versionCode from CI run, docs/RELEASE.md. The owner still needs to run the real-phone checklist (docs/TESTING.md) |
| 9 — Remote MCP server (owner request) | **Removed in Sapphire** | Replaced by direct GitHub sync (Phase 10). Was: PR #11 server (`mcp-server/`, Vercel): read tools + proposals only, 16 tests incl. end-to-end with the official MCP client, real GitHub API check. PR #12 app inbox (Settings → GitHub sync → AI app proposals). Not yet deployed to Vercel or used from a real AI app (needs the owner's accounts) |
| 10 — Sapphire: rebrand, GitHub sign-in, auto sync, new graph | Done in CI | Sapphire name/palette/logo; MCP server and proposal inbox removed; Sign in with GitHub (device flow, GitHub App limited to the notes repo); automatic two-way sync with mirrored deletions and a mass-delete brake; live-physics graph (grab, drag with linked notes, 2D↔3D morph, orbit, solid group colours). Real phone + real GitHub App not yet exercised |

Testing levels are reported separately: unit/widget tests (CI), CI APK build,
emulator tests, and real-device tests. A phase is not marked "Done" for
behavior that was only compiled.

## Verification summary (October 2026)

| Level | Status |
| --- | --- |
| Unit + widget tests | Run in CI on every PR (205+ tests) |
| Release APK build | Built in CI on every PR; artifact `sapphire-android-apk` |
| Emulator (API 34) | Launch, navigation, real SAF channel restore, core note flows with an in-memory vault, Keystore secure storage, app-private files (4 tests, all passing in CI) |
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
- No streaming AI replies; sync runs while the app is open (not when fully closed).
- License not chosen yet (LICENSE_DECISION.md).
