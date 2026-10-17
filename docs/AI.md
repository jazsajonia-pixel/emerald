# AI in Emerald (Phase 5)

AI is optional. Emerald works fully without it, sends nothing anywhere until
you add your own API key, and asks for consent before the first request.

## How it works

```
AI Hub UI ──> ChatController ──> AiProvider (adapter interface)
                   │                  └── GeminiProvider (HTTP, user's key)
                   └──> VaultTools (vault-scoped) ──> NoteRepository / VaultIndex
                              └── create/update → NoteProposal (pending)
                                                    └── user approves → ProposalApplier
```

- `lib/features/ai/ai_types.dart` — provider-independent types: messages,
  tool specs, tool calls, capabilities, typed errors (`AiErrorCode`).
- `lib/features/ai/providers/gemini_provider.dart` — the only provider
  adapter so far. New providers implement `AiProvider` and are added to
  `providerCatalog` and `aiProviderFactoryProvider` in `ai_config.dart`.
- `lib/features/ai/tools/vault_tools.dart` — the tools the model may call.
- `lib/features/ai/chat_controller.dart` — the tool loop (max 8 model calls
  per question).
- `lib/features/ai/proposals.dart` — proposals and the conflict-safe applier.

## Tools offered to the model

| Tool | Effect |
| --- | --- |
| `search_notes` | Full-text search; returns paths, titles, snippets |
| `list_notes` | Lists note paths (optionally one folder) |
| `read_note` | Returns one note's Markdown (truncated at 20,000 chars) |
| `find_backlinks` | Notes linking to a note |
| `find_related_notes` | Related by explicit links only (no semantic inference) |
| `create_note` | Records a proposal only — nothing is written |
| `update_note` | Records a proposal with a diff — nothing is written |

There is no delete, rename or move tool. Every path is validated with the same
`VaultPath` rules as the editor and must be an existing indexed `.md` note, so
the model cannot reach files outside the vault, hidden folders, or non-notes.
At most 10 proposals per conversation.

## Approval flow

1. Proposals appear as cards with a line diff (+/−) and a summary.
2. "Approve & save" writes through the normal note repository: the previous
   version goes to history, and the write is refused if the note changed
   after the proposal was made (hash check), so outside edits are never lost.
   Creates never overwrite an existing file.
3. "Reject" changes nothing.
4. "Review & apply all" (shown when several proposals are pending) lists every
   change and requires an explicit "Apply all" confirmation.

## Data sharing and privacy

- The AI Hub shows which notes were sent ("Sent to Google Gemini: N notes").
  Only your question, search results (paths/titles/snippets), and notes the
  model chose to read are sent.
- Requests go directly from the phone to the provider; there is no Emerald
  server.
- The key is stored with `flutter_secure_storage` (Android Keystore-backed),
  never written to the vault, never displayed after saving, never logged, and
  never included in error messages (covered by tests). Android auto-backup is
  disabled for the app (`allowBackup="false"`).
- Gemini free tier: Google's pricing page states free-tier content may be used
  to improve Google products; paid-tier content is not. Emerald shows this in
  the consent dialog and settings.

## Gemini setup (user)

1. Create a key in Google AI Studio (aistudio.google.com → Get API key).
2. Emerald → Settings → AI provider → paste key → "Test connection" (lists
   models; does not use generation quota) → pick a model → Save.
3. Default model: `gemini-3.8-flash` (from the official models page at the
   time of writing). Any model ID returned by "Test connection" can be used.

## Verified API facts (checked October 2026)

| Fact | Source |
| --- | --- |
| `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | https://ai.google.dev/api/generate-content |
| `GET …/v1beta/models` with `pageToken`/`nextPageToken`, `supportedGenerationMethods` | https://ai.google.dev/api/models |
| API key header `x-goog-api-key` | https://ai.google.dev/api/generate-content |
| `tools[].functionDeclarations[]` with `parametersJsonSchema`; `functionCall {id,name,args}`; `functionResponse {id,name,response}` | https://ai.google.dev/gemini-api/docs/function-calling |
| Model parts may carry `thoughtSignature` and must be sent back unchanged | https://ai.google.dev/gemini-api/docs/function-calling |
| Model IDs | https://ai.google.dev/gemini-api/docs/models |
| Free/paid tiers and data use | https://ai.google.dev/gemini-api/docs/pricing |

## Capability matrix

| Capability | Gemini adapter |
| --- | --- |
| Text answers | Yes |
| Tool use | Yes |
| Streaming | Not implemented (full responses only) |
| Model listing | Yes |

## Limits and known gaps

- No streaming; a long answer appears all at once (60 s timeout).
- Conversation history is in memory only and lost when the app closes.
- Related-note suggestions use explicit links only; AI-inferred links in the
  graph are not implemented yet (the graph reserves a separate edge kind).
- The real Gemini API was not called during development (no key, no paid
  usage). The adapter is tested against recorded request/response shapes from
  the official docs with a mock HTTP client. A real-key check is in the manual
  checklist (docs/TESTING.md).
