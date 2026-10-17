# Emerald architecture

Emerald keeps UI, Markdown storage, AI integrations, and sync separate so each
can evolve (or be replaced) without touching the others.

```
lib/
  main.dart            App entry point
  app/                 App widget, theme, top-level navigation
  core/                Errors, shared UI, security/path utilities
  data/                Repositories and platform adapters (e.g. Android SAF channel)
  features/
    vault/             Folder selection, file listing, read/write
    notes/             Note list, editor, preview, backlinks
    search/            Indexing and search
    graph/             Graph model, layout, interaction
    ai/                Provider-neutral interface, adapters, tools, approvals
    settings/          Theme, vault, provider configuration
android/app/src/main/kotlin/...   Small Kotlin platform channel for Storage Access Framework
```

## Key decisions

- **Source of truth:** the user's `.md` files. Any index/cache is derived data
  and can be rebuilt from the files at any time; rebuilding never modifies or
  deletes notes.
- **Vault access:** Android Storage Access Framework (`ACTION_OPEN_DOCUMENT_TREE`
  plus persisted URI permissions) through a small Kotlin platform channel, not
  raw filesystem paths. See [`STORAGE.md`](STORAGE.md) for the safety rules and
  limitations.
- **State management:** Riverpod 3 (`flutter_riverpod`), no code generation.
- **Markdown preview:** `flutter_markdown_plus` (maintained successor of the
  discontinued `flutter_markdown`). Remote images are never loaded.
- **Hashing:** `crypto` (SHA-256 for conflict detection).
- **Graph:** explicit Markdown/wiki links first. AI-inferred links, if ever
  added, are a separate, visually distinct layer.
- **AI:** provider-neutral interface; each provider lives in its own adapter.
  AI-proposed edits are previewed and require approval.
- **Dependencies:** each one must be maintained, Android-compatible, and have a
  clear purpose. No cloud backend, vector DB, or agent framework without a
  tested requirement.

The sections above are updated as each phase lands.
