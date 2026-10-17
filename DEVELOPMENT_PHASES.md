# Emerald — Development Phases and Acceptance Criteria

This roadmap is designed for a phone-only project workflow using Perplexity with GitHub repository access. Work in small increments. Do not skip acceptance checks to reach the final APK faster.

## Phase 0 — Repository and build foundation

### Tasks
- Inspect the existing `emerald` repository before changing anything.
- Check whether it is empty or already contains work; preserve useful files.
- Create a Flutter project with Android support and a documented package/application ID.
- Add `.gitignore`, `README.md`, license decision placeholder if not supplied, and a concise architecture note.
- Add GitHub Actions for `flutter format` validation, `flutter analyze`, tests, and a debug/release APK build as appropriate.
- Pin or document the Flutter stable version used by CI.
- Add no credentials or personal vault content.

### Acceptance criteria
- Repository clones cleanly.
- Flutter project resolves dependencies.
- Formatting, analysis, tests, and Android build run in CI.
- APK is downloadable from a successful GitHub Actions run.
- Main remains buildable.

## Phase 1 — Emerald shell and navigation

### Tasks
- Build a mobile-first Material 3 interface with Emerald branding.
- Create navigation for Home, Brain/Notes, Graph, AI Hub, and Settings.
- Add loading, empty, error, and permission-denied states.
- Ensure touch targets, text scaling, contrast, and narrow-screen layouts are usable.

### Acceptance criteria
- App launches on Android.
- Navigation works without crashes.
- No screen is merely a placeholder pretending to be implemented; label incomplete functionality clearly.
- Widget tests cover primary navigation and important empty/error states.

## Phase 2 — Safe Markdown vault access

### Tasks
- Let the user choose a vault folder using Android's supported folder picker / Storage Access Framework.
- Persist the granted folder permission where Android allows.
- List folders and Markdown files; ignore internal app files and unsafe paths.
- Read Markdown files and create/edit/save notes.
- Handle UTF-8, empty files, large files reasonably, permission revocation, missing files, and I/O failures.
- Detect external changes and avoid silently overwriting newer content.
- Add a basic editor and optional rendered preview.
- Do not copy the entire vault into app-private storage as an undocumented substitute for live access.

### Acceptance criteria
- User can select an existing vault and see its `.md` files.
- User can open, create, edit, save, close, and reopen notes.
- Saved changes are visible to another Markdown editor when that editor can access the same folder.
- Tests cover path validation, read/write, errors, and conflict behavior.
- Any Android storage limitation is documented honestly.

## Phase 3 — Markdown links, backlinks, and search

### Tasks
- Parse standard relative Markdown links.
- Add practical support for Obsidian wiki links such as `[[Note Name]]` and aliases such as `[[Note Name|display text]]`.
- Build a local metadata/index database that can be regenerated from Markdown.
- Search titles and contents.
- Show backlinks and orphan/unlinked notes.
- Refresh the index after Emerald writes files and provide a manual rescan for external edits.

### Acceptance criteria
- Search returns correct matching notes.
- Links resolve safely without escaping the vault.
- Backlinks are consistent with the current file contents.
- Index can be rebuilt without modifying or deleting source notes.
- Tests cover broken links, duplicate names, renamed/missing notes, and Unicode text.

## Phase 4 — Interactive graph

### Tasks
- Build a global graph from explicit links and a local graph centered on the selected note.
- Provide touch gestures for pan, zoom, and node selection.
- Tapping a node opens its note.
- Add search/highlighting and basic filters.
- Visually distinguish linked notes, isolated notes, and any future inferred relationships.
- Keep graph layout responsive; test larger vaults and avoid blocking the UI during indexing.
- Choose a maintained package only after reviewing Android compatibility, maintenance, and license.

### Acceptance criteria
- Graph edges match the parsed explicit links.
- Selecting a node opens the expected note.
- Graph updates after notes are changed or rescanned.
- Graph is usable on a phone and handles an empty vault and disconnected nodes.
- Performance limits and any node-count constraints are documented.

## Phase 5 — AI foundation and safe tools

### Tasks
- Define a provider-neutral AI interface and isolate provider-specific adapters.
- Add settings for provider selection and credential entry.
- Store credentials using Android-secure storage; never commit or log them.
- Implement one direct API integration only after checking current official documentation, model availability, pricing, tool-calling support, and terms.
- Provide controlled tools for search, list, read, backlinks, and related notes.
- Add a proposal/approval flow for creating and updating notes.
- Send only the selected relevant context to remote services; explain that remote AI requests transmit the chosen note content.
- Handle timeouts, rate limits, malformed responses, and usage errors gracefully.

### Acceptance criteria
- A configured provider can answer a question using retrieved notes.
- AI can search and read only within the approved vault scope.
- A proposed edit is previewed and not applied until approved.
- API errors do not corrupt files or crash the app.
- API keys never appear in logs, repository history, or exported Markdown.
- No unsupported claim is made about integrations or subscriptions.

## Phase 6 — Additional AI providers and external agents

### Tasks
- Add more providers through the same interface, one at a time.
- Research current official documentation before each integration.
- Integrate external agents only through a verified supported API, protocol, or connector.
- If MCP is used, document whether Emerald is an MCP client, whether a server is required, how it is hosted, and how authentication works.
- Do not assume a remote agent can access Android storage directly.
- Add a provider capability matrix showing which providers support text, tool use, streaming, and other required features.

### Acceptance criteria
- Switching providers does not alter Markdown data or require a vault migration.
- Each integration has tests or a documented manual verification procedure.
- Unsupported features are disabled or clearly explained rather than simulated.
- Per-provider setup, data sharing, and cost considerations are documented.

## Phase 7 — Backup and hybrid synchronization

### Tasks
- First define the supported sync target and conflict policy; do not silently select a cloud service or require paid infrastructure.
- Implement optional remote backup/sync only after local file operations are stable.
- Track file identity, modified time, and content hashes where useful.
- Detect simultaneous edits and provide conflict copies or a merge UI.
- Do not delete local notes just because a remote copy is missing.
- Provide sync status, retry, and error messages.
- Keep sync credentials secure.

### Acceptance criteria
- Local-only use remains functional without network access.
- Sync failures never silently discard edits.
- Conflicts are visible and recoverable.
- Users can disable sync.
- Setup instructions describe where data is stored and which services receive it.

## Phase 8 — Release hardening and downloadable APK

### Tasks
- Run formatting, static analysis, all tests, and a clean release build.
- Fix all known critical/high-severity issues and investigate warnings.
- Test install, launch, vault selection, note save/reopen, search, graph navigation, and error cases on Android or a documented emulator/device environment.
- Generate a release APK and publish it as a GitHub Actions artifact.
- Optionally create a GitHub Release only if repository permissions and release credentials are available.
- Document installation, Android unknown-source warnings, permissions, limitations, and upgrade behavior.
- Do not commit a signing key. If a signed distributable is needed, document secure signing setup separately.

### Acceptance criteria
- A real APK file is attached to a successful CI run or release.
- The artifact link works and the APK is not merely a source archive.
- Build/test status and device testing status are reported truthfully.
- `main` is updated only after review and all required checks pass.
- If any critical test fails, do not merge; report the blocker and fix it first.

## Final product checklist

- [ ] Native Android Flutter app
- [ ] User-selected Markdown vault
- [ ] Read/create/edit/save notes safely
- [ ] Search, links, and backlinks
- [ ] Global and local graph
- [ ] Provider-independent AI architecture
- [ ] At least one verified AI integration
- [ ] Safe AI change approval
- [ ] Optional hybrid sync with conflict handling
- [ ] Automated CI and tests
- [ ] Downloadable APK artifact
- [ ] Setup, privacy, and limitations documentation
- [ ] `main` passes checks and contains only verified working changes
