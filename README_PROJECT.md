# Emerald — Project Overview

> **Emerald** is a mobile-first, local-first AI knowledge app for Android. It works with ordinary Markdown files, presents their connections in an interactive knowledge graph, and provides a provider-independent way for compatible AI services to search and work with the user's knowledge.

## Product vision

Emerald should help its owner maintain one portable knowledge base that can be used by different AI models and agents without repeatedly uploading notes. The user develops the project entirely on an Android phone and uses Perplexity with GitHub repository access to help implement it.

**GitHub repository:** `emerald`

**Primary platform:** Android  
**Initial implementation:** Flutter + Dart  
**Knowledge format:** Plain Markdown (`.md`) files  
**Source of truth:** User-owned Markdown files, not a proprietary database

## Core principles

1. **Local-first and portable.** Read and write ordinary Markdown files in a user-selected vault. Preserve compatibility with Obsidian and other Markdown editors.
2. **Provider-independent AI.** Separate the app's AI tools and conversation interface from individual model/provider implementations.
3. **No false integrations.** Integrate an external agent such as Manus only through a real, documented, permitted API, connector, or supported protocol. Do not pretend an ordinary chat subscription automatically grants API access.
4. **Safe file operations.** Validate paths, preserve existing content, show previews for meaningful edits, keep recoverable history where feasible, and never silently overwrite conflicting changes.
5. **Useful graph, not decoration.** Visualize explicit Markdown links first. Treat AI/semantic relationships as suggestions and label them clearly.
6. **Mobile-first.** Main workflows must be usable on a typical Android phone, including narrow screens and touch input.
7. **No secrets in Git.** Never commit API keys, tokens, signing passwords, private user notes, or local configuration containing secrets.
8. **Build in working increments.** Every phase should leave the repository in a coherent, buildable state.

## MVP scope

### Required for the first usable release
- Flutter Android app with a consistent Emerald visual identity (dark theme with restrained emerald-green accents; accessible contrast).
- Select a Markdown vault directory using Android's supported document/folder picker and persist access where Android permits.
- Browse folders and `.md` files.
- Read, create, and edit Markdown notes.
- Search note titles and contents.
- Support standard Markdown links and Obsidian-style wiki links such as `[[My Note]]` where practical.
- Show backlinks and a useful global/local graph based on explicit links.
- Handle file read/write errors and external changes without data loss.
- Automated tests and a reproducible Android APK build.
- GitHub Actions workflow that builds the APK and publishes it as a downloadable workflow artifact.

### Planned after the MVP
- AI chat with a provider abstraction and one verified direct API integration.
- Controlled tools for AI to search/read notes and propose/create/update notes.
- Additional providers and supported external-agent integrations.
- Optional remote backup/sync and conflict resolution.
- Semantic graph connections using embeddings or AI, with clear visual distinction from explicit links.
- More robust history, restore, import/export, and release automation.

## Proposed technology stack

Use the latest mutually compatible **stable** versions available when implementation begins. Check official documentation and package maintenance before selecting dependencies; do not blindly copy stale versions.

- **Language/UI:** Flutter + Dart, Material 3.
- **State management:** Choose one maintained approach (Riverpod is the preferred candidate unless project constraints justify another). Keep state management consistent.
- **Navigation:** Choose a maintained Flutter routing package if needed; avoid unnecessary dependencies.
- **Markdown rendering/editing:** Select maintained packages after checking Android support, security, and license. Editing may initially use a reliable plain text editor with Markdown preview rather than a complex editor.
- **Local metadata/index:** SQLite via a maintained Flutter package such as `sqflite` or Drift, only for metadata/search/index state. Markdown files remain authoritative.
- **Vault access:** Prefer Android Storage Access Framework/document-tree access through a maintained Flutter plugin or a small, documented Kotlin platform-channel implementation. Verify persisted URI permission behavior on real Android versions. Do not assume ordinary `dart:io` file paths can access every user-selected Android folder.
- **Graph:** Use a maintained Flutter graph/visualization package if it meets touch, layout, and performance needs; otherwise build a focused custom graph view. Confirm package health, license, and Android compatibility first.
- **Secrets:** Use Android Keystore-backed secure storage via a maintained Flutter package for locally stored API credentials. Do not store secrets in Markdown or source control.
- **Tests:** Dart unit tests, Flutter widget tests, and Android build checks.
- **CI:** GitHub Actions to run formatting, analysis, tests, and build a release-mode APK artifact.

Do not add a cloud backend, graph database, vector database, or complex agent framework until a tested requirement justifies it.

## Architecture boundaries

Keep the app divided into clear layers, for example:

- `features/vault/`: folder selection, file listing, read/write, Markdown links.
- `features/notes/`: note list, editor, preview, backlinks.
- `features/graph/`: graph data model, layout, interactions, filters.
- `features/search/`: indexing and search.
- `features/ai/`: provider interface, tool definitions, approval workflow.
- `features/settings/`: theme, vault, provider configuration.
- `data/`: repositories and platform-specific adapters.
- `core/`: error handling, logging, shared UI, security utilities.

Adapt this structure if there is a clear technical reason, but preserve separation between UI, Markdown storage, AI integrations, and sync.

## AI integration design

Define a provider-neutral interface before adding multiple providers. Keep provider-specific request/response handling in adapters. The app should expose narrowly scoped tools such as:

- `search_notes`
- `list_notes`
- `read_note`
- `find_backlinks`
- `find_related_notes`
- `propose_note_changes`
- `create_note`
- `update_note`

AI access must be scoped to the selected vault and validated note paths. For initial AI-enabled releases, show a preview and request user approval before applying substantive edits. Deletes and bulk edits require explicit confirmation. Record what changed where feasible.

**External-agent caveat:** An agent like Perplexity or Manus can only operate on the repository/files and APIs it is actually authorized to access. Do not invent endpoints or claim that a consumer chat account provides API access. Verify current official docs before implementing each integration. A GitHub connector is not the same as direct access to the phone's local vault.

## File safety and data integrity

- Treat note content as user data.
- Reject path traversal and writes outside the selected vault.
- Do not follow symlinks or other path escapes without a deliberate safe design.
- Use atomic writes where supported (write temporary content, then replace).
- Detect changes between read and write; surface conflicts instead of silently overwriting.
- Never automatically delete user notes during indexing or sync.
- Provide clear error states and recovery guidance.
- Do not send vault contents to any remote AI unless the user explicitly configures and invokes that integration.
- Keep logs free of note contents, API keys, and personal data by default.

## Definition of done for an MVP

A phase is complete only when:
- The implementation is committed to a feature branch or pull request.
- Formatting and static analysis pass.
- Relevant automated tests pass.
- The Android release APK builds successfully.
- A reviewer can follow the documented setup and reproduce the result.
- Known limitations are documented.
- No secrets or private notes have been committed.

The repository's `main` branch must remain buildable. Merge only after checks pass and the changes have been reviewed. If the environment does not support opening/merging pull requests, explain the limitation and provide the branch/commit and exact next steps rather than claiming a merge occurred.
