# AI in Emerald (Phases 5–6)

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
- `lib/features/ai/providers/gemini_provider.dart` — Google Gemini adapter.
- `lib/features/ai/providers/openai_compatible_provider.dart` — adapter for
  any server implementing the OpenAI Chat Completions API (OpenAI itself,
  Ollama, and similar). New providers implement `AiProvider` and are added to
  `providerCatalog` and `aiProviderFactoryProvider` in `ai_config.dart`.
- Settings are stored per provider (`ai.<provider>.apiKey/model/baseUrl/
  reasoningEffort`), so switching providers keeps each one's settings and
  never touches the vault — no migration is ever needed.
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
- Each provider's data notice is shown in the consent dialog and settings:
  - Gemini free tier: Google's pricing page states free-tier content may be
    used to improve Google products; paid-tier content is not.
  - OpenAI: "data sent to the OpenAI API is not used to train or improve
    OpenAI models (unless you explicitly opt in)"; abuse-monitoring logs are
    kept for up to 30 days (https://platform.openai.com/docs/guides/your-data).
  - Other OpenAI-compatible servers: their own policy applies. A server on
    `localhost` keeps everything on the phone.
- Network: HTTPS only. Plain HTTP is allowed solely to `localhost` /
  `127.0.0.1` (Android network security config + URL validation), so a key or
  note can never be sent unencrypted over a network.

## Gemini setup (user)

1. Create a key in Google AI Studio (aistudio.google.com → Get API key).
2. Emerald → Settings → AI provider → paste key → "Test connection" (lists
   models; does not use generation quota) → pick a model → Save.
3. Default model: `gemini-3.8-flash` (from the official models page at the
   time of writing). Any model ID returned by "Test connection" can be used.

## OpenAI-compatible setup (user)

- **OpenAI** (paid, billed per token by OpenAI; no free API tier is assumed):
  base URL `https://api.openai.com/v1`, key from platform.openai.com. Tool use
  through Chat Completions is limited on OpenAI's newest models: OpenAI
  documents `gpt-6-luna` function calling over Chat Completions only with
  `reasoning_effort: "none"`, and states GPT-6 Astra / GPT-6.1 Sol do not
  support function calling there. Use model `gpt-6-luna` and set
  "Reasoning effort" to `none`. (Example price from OpenAI's model page:
  $0.10 / 1M input tokens, $0.50 / 1M output tokens for gpt-6-luna.)
- **Ollama on the phone** (free, local; e.g. installed in Termux): base URL
  `http://localhost:11434/v1`, leave key empty, model = a pulled model that
  supports tools. Note search needs a tool-capable model.
- **Other servers**: any HTTPS endpoint implementing `/chat/completions` and
  `/models`. Emerald does not claim support for a specific vendor beyond the
  documented API shape; verify with "Test connection" and the manual steps.
- "Reasoning effort" is only sent when filled in, because not every server
  accepts the field.

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
| OpenAI `POST /chat/completions`: roles, `tools[{type:function,function:{name,description,parameters}}]`, `tool_calls[].function.arguments` (JSON string), `{role:tool,tool_call_id}` | https://platform.openai.com/docs/api-reference/chat/create |
| OpenAI `GET https://api.openai.com/v1/models`, `Authorization: Bearer` | https://platform.openai.com/docs/api-reference/models/list |
| OpenAI 401/403/429 (rate vs `insufficient_quota`, spend-limit codes)/500/503 | https://platform.openai.com/docs/guides/error-codes |
| gpt-6-luna endpoints, function-calling restriction, price | https://platform.openai.com/docs/models/gpt-6-luna |
| Astra/Sol: no function calling via Chat Completions; `reasoning_effort` values | https://platform.openai.com/docs/guides/reasoning |
| Ollama OpenAI compatibility (`/v1/chat/completions` with tools, `/v1/models`, port 11434, key ignored locally) | https://docs.ollama.com/api/openai-compatibility |

## Capability matrix

| Capability | Gemini | OpenAI-compatible |
| --- | --- | --- |
| Text answers | Yes | Yes |
| Tool use (search/read, proposals) | Yes | Yes, if the model/server supports Chat Completions function calling (see above) |
| Streaming | Not implemented | Not implemented |
| Model listing | Yes (`generateContent` models only) | Yes (all IDs the server returns) |
| Key required | Yes | Yes, except `localhost` servers |
| Free option | Free tier (rate-limited; data may be used by Google) | Local Ollama (free, on-device) |

If a model cannot use tools, the provider returns an error that Emerald shows
as-is; tool use is never simulated.

## MCP and external agents

**Phone app:** Emerald itself does not run an MCP server or client. A remote
agent cannot reach an app on a phone or read Android Storage Access Framework
folders, and stdio transport (client launches the server as a subprocess)
does not apply to an Android app
(https://modelcontextprotocol.io/specification/latest/basic/transports).

**Remote MCP server (owner-requested, Phase 9):** ChatGPT, Claude,
Perplexity and Manus connect to custom connectors from their own clouds over
public HTTPS. The optional server in `mcp-server/` (deployed by the owner on
Vercel) provides that endpoint and works on the GitHub sync repository:

- Read tools: list, read, search, backlinks — Markdown notes only, hidden
  folders excluded.
- One write tool, `propose_note_change`, which stores a proposal in
  `.emerald/proposals/` and never edits a note. The owner reviews the diff and
  approves or rejects it in Emerald (same rule as in-app AI). No delete or
  rename tools.
- Access by a shared secret (header or `?key=`) stored in Vercel environment
  variables, plus a fine-grained GitHub token limited to the sync repo.

Setup, security notes and per-app connection steps: `mcp-server/README.md`.

**Emerald as MCP client** (giving the in-app AI extra tools from remote MCP
servers) is not implemented: it would widen what data leaves the phone and is
not needed for the vault tools, which Emerald implements natively.

## Manual verification per provider

The agent that built Emerald did not call any real provider (no keys; no paid
usage). Automated tests use a mock HTTP client with request/response shapes
from the official docs. Before relying on a provider, follow
docs/TESTING.md steps 14–21.

## Limits and known gaps

- No streaming; a long answer appears all at once (60 s timeout).
- Conversation history is in memory only and lost when the app closes.
- Related-note suggestions use explicit links only; AI-inferred links in the
  graph are not implemented yet (the graph reserves a separate edge kind).
- No real provider API was called during development (no keys, no paid
  usage). Adapters are tested against request/response shapes from the
  official docs with a mock HTTP client. Real-key checks are in the manual
  checklist (docs/TESTING.md).
