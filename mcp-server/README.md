# Emerald MCP server (for ChatGPT, Claude, Perplexity, Manus …)

A small remote [MCP](https://modelcontextprotocol.io) server you deploy for
free on Vercel. AI apps connect to it as a **custom connector** and can then
read and search your Emerald vault and **propose** changes. Nothing in a note
changes until you review the diff and approve it in the Emerald app.

```
AI app (cloud) ──HTTPS + secret──▶ this server (Vercel) ──GitHub API──▶ your private sync repo
                                                                          ▲
                                     Emerald on your phone ── Sync now ───┘
```

It works on the **GitHub copy** of your vault, so it needs Emerald's GitHub
sync (Settings → GitHub sync) set up first. Tap **Sync now** before asking an
AI about recent edits. Proposals appear in Emerald under Settings → GitHub
sync → **AI app proposals**.

## Tools

| Tool | What it does |
| --- | --- |
| `list_notes` | Lists Markdown notes (optionally in one folder) |
| `read_note` | Returns a note's text and its version id |
| `search_notes` | Full-text search over titles and contents |
| `find_backlinks` | Notes that link to a note (`[[wiki]]` or Markdown links) |
| `list_pending_proposals` | Proposals still waiting for your approval |
| `propose_note_change` | Saves a proposal to create a note or replace its text |

Not possible: deleting, renaming, or directly editing notes; reading hidden
folders (e.g. `.obsidian/`) or non-Markdown files. Proposals are stored in
`.emerald/proposals/` in the repository (a hidden folder sync never copies
into your vault). At most 50 can wait at once; each note is limited to 512 KB.

## Deploy on Vercel (free Hobby plan)

The Hobby plan is for personal, non-commercial use.

1. **GitHub token for the server.** GitHub → Settings → Developer settings →
   Personal access tokens → Fine-grained tokens → Generate new token.
   *Only select repositories* → your Emerald sync repository. Permissions:
   **Contents: Read and write** (Metadata: Read is added automatically).
   Use a separate token from the one on your phone so you can revoke each
   independently.
2. **Access secret.** Make a random string of at least 32 characters, e.g.
   on a computer: `openssl rand -hex 32`. Anyone with it can read your notes
   through the server, so treat it like a password.
3. **Create the Vercel project.** vercel.com → Add New → Project → import
   the `emerald` GitHub repository → set **Root Directory** to
   `mcp-server`. Framework preset: **Other**. Leave build settings empty.
4. **Environment variables** (same screen, or Project → Settings →
   Environment Variables), for Production:

   | Name | Value |
   | --- | --- |
   | `EMERALD_GITHUB_OWNER` | owner of the sync repo, e.g. `your-name` |
   | `EMERALD_GITHUB_REPO` | sync repo name, e.g. `my-vault` |
   | `EMERALD_GITHUB_BRANCH` | branch Emerald syncs (default `main`) |
   | `EMERALD_GITHUB_TOKEN` | the token from step 1 |
   | `EMERALD_MCP_SECRET` | the secret from step 2 |

5. **Deploy.** Your endpoint is `https://<project>.vercel.app/api/mcp`.
   Opening it in a browser without the secret shows
   `{"error":"Missing or wrong access secret."}` — that means it is running.
   `Server is not configured` names any missing variable.

Optional: Project → Settings → Git → **Ignored Build Step** →
`git diff --quiet HEAD^ HEAD -- .` so app-only commits do not redeploy.

If you change a variable, redeploy (Deployments → ⋯ → Redeploy).

## Connect an AI app

The secret can be sent three ways: `Authorization: Bearer <secret>`,
`X-API-Key: <secret>`, or `?key=<secret>` at the end of the URL. Prefer a
header when the app supports one; a secret in a URL can end up in logs and
screenshots.

- **Claude** (web/desktop; then also usable in the mobile app): Customize →
  Connectors → Add → Custom → Web. URL: your endpoint. Authentication:
  **No sign in**. Request headers: `Authorization` = `Bearer <secret>`.
  Free plans allow one custom connector.
- **Perplexity**: Plugins → Add custom → Connector → Add MCP connector →
  Remote. URL: your endpoint. Transport: Streamable HTTP. Authentication:
  **API Key** with your secret. If the connection is refused, use
  Authentication **None** with `…/api/mcp?key=<secret>`.
- **Manus**: Settings → Connectors → Add connectors → Custom MCP → Add
  custom MCP server → Direct configuration. Transport: HTTP. URL: your
  endpoint. Custom header `Authorization` = `Bearer <secret>`.
- **ChatGPT**: Plugins → + → Add custom MCP server. URL:
  `…/api/mcp?key=<secret>`. Authentication: **No authentication**.
  OpenAI currently lists custom MCP servers for Business and
  Enterprise/Edu plans on ChatGPT web; check your plan.

Then ask, e.g., "Using Emerald, find my notes about tomatoes and propose a
summary section for Garden.md". In Emerald: Settings → GitHub sync → **AI app
proposals** → review the diff → **Approve & save** (or Reject) → **Sync now**
to upload the approved change.

Menu names above follow each provider's help pages as of October 2026 and
may change. These setups were not tested end to end with each app; the
server itself is tested with the official MCP client (see Testing).

## Security notes

- The server can read every Markdown note in the sync repo and create files
  only under `.emerald/proposals/`. It cannot delete or overwrite files
  (GitHub refuses a create when the file exists).
- The GitHub token and access secret live only in Vercel's environment
  variables; they are never returned in responses or error messages
  (tested). Revoke the GitHub token or change `EMERALD_MCP_SECRET` (then
  redeploy) to cut off access immediately.
- AI apps you connect see the notes their tools return, under that
  provider's terms. Only connect apps you trust.

## Development

Node.js 24 (Vercel's default; 20+ works for tests).

```sh
cd mcp-server
npm ci
npm run typecheck
npm test        # unit tests + end-to-end tests with the official MCP client
```

`api/mcp.ts` is the Vercel Function; logic is in `src/`. Tests use an
in-memory fake of the GitHub API (`test/fake_github.ts`).
