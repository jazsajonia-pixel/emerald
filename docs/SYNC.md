# GitHub sync (Phase 7)

Optional, off by default. Emerald works fully offline without it.

## Target (decided by the project owner)

Two-way sync of the vault's Markdown notes with **one branch of one GitHub
repository you own**, using a fine-grained personal access token. No Emerald
server, no paid service: requests go directly from the phone to
`https://api.github.com`. GitHub's free plan includes private repositories.

## What is synced

- All `.md` files in the vault, in the same folder structure (repository root
  = vault root).
- Not synced: hidden files/folders (e.g. `.obsidian/`), non-Markdown files,
  files over 8 MB (listed as notices).
- Sync runs only when you tap **Sync now** (no background sync).

## Conflict policy

Emerald compares three Git blob hashes per file: on the phone, on GitHub, and
at the last successful sync (stored in app-private storage, not in the vault).

| Phone | GitHub | Result |
| --- | --- | --- |
| changed | unchanged | upload (one commit per file) |
| unchanged | changed | download; the old local version goes to note history |
| changed | changed (differently) | **conflict**: GitHub's version is saved as `Title (GitHub conflict YYYY-MM-DD HHMM).md` next to your note; your note is untouched. The next sync uploads your note and the conflict copy. Merge them by hand when you like. |
| new | absent | upload |
| absent | new | download (folders created as needed) |
| both new, different | | conflict (as above) — e.g. first sync with an existing repo |
| deleted | unchanged | **kept on GitHub** (notice); nothing is deleted |
| unchanged | deleted | **kept on the phone** (notice); not re-uploaded unless you edit it |
| deleted | changed | restored from GitHub |
| changed | deleted | re-uploaded |

Sync never deletes a file on either side. Every local overwrite re-reads the
file and is refused if it changed since the comparison; every GitHub update
sends the expected blob SHA, and GitHub refuses it (409) if the file changed
meanwhile. Refused files are listed and retried on the next sync, where they
become conflicts — nothing is lost. Downloaded content is verified against its
Git blob hash before it is written.

Switching to another repository/branch starts with an empty sync history, so
the first sync with it is conservative (differences become conflicts).

## Setup

1. On GitHub, create a **private** repository and initialise it with a README
   (an empty repository cannot be listed; Emerald reports this).
2. GitHub → Settings → Developer settings → Personal access tokens →
   **Fine-grained tokens** → Generate new token: *Only select repositories* →
   that repository; Repository permissions: **Contents: Read and write**,
   **Metadata: Read**. Pick an expiration.
3. Emerald → Settings → **GitHub sync** → owner, repository, branch, token →
   **Test connection** (read-only) → **Save settings** → **Enable GitHub sync**
   → **Sync now**.

A public repository is refused unless you turn on "Allow a public repository"
and confirm, because every synced note would be readable by anyone.

## Where data goes

- Note content: your phone and the GitHub repository (GitHub's terms and
  privacy statement apply). Commit messages contain the note path, e.g.
  `Update Projects/Plan.md (Emerald sync)`.
- Token: Android Keystore-backed secure storage on the phone; never written
  to the vault, never displayed after saving, never logged or included in
  error messages (tested). **Remove** deletes it (and the sync history) from
  the phone without touching notes or the repository. You can also revoke it
  on GitHub at any time.
- Sync history (hashes, sizes, times — no note content): app-private storage.

## Disabling

Turn off **Enable GitHub sync** (settings kept) or tap **Remove** (settings,
token and sync history deleted). Local notes are never affected.

## Verified API facts (October 2026)

| Endpoint / fact | Source |
| --- | --- |
| `PUT /repos/{owner}/{repo}/contents/{path}` (message, base64 content, `sha` when updating, branch; 200/201/404/409/422; Contents: write; must be used serially) | https://docs.github.com/en/rest/repos/contents |
| `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1` (`truncated`; 100,000 entries / 7 MB limit; Contents: read) | https://docs.github.com/en/rest/git/trees |
| `GET /repos/{owner}/{repo}/git/blobs/{sha}` (base64 content, up to 100 MB; Contents: read) | https://docs.github.com/en/rest/git/blobs |
| `GET /repos/{owner}/{repo}` (`private`, `permissions.push`; Metadata: read) | https://docs.github.com/en/rest/repos/repos#get-a-repository |
| `X-GitHub-Api-Version: 2022-11-28` supported until 2028-03-10 | https://docs.github.com/en/rest/about-the-rest-api/api-versions |
| Fine-grained token creation steps | https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens |

Not documented on those pages and therefore handled defensively: GitHub's
response for an empty repository's tree (Emerald treats `409` there as
"empty repository" and stops without changes).

## AI app proposals (optional MCP server)

The optional server in `mcp-server/` lets AI apps read the GitHub copy of the
vault and store proposals in `.emerald/proposals/` (a hidden folder, so sync
never copies it into the vault). Settings → GitHub sync → **AI app
proposals** lists them:

- **Ready**: the note on the phone is exactly the version the AI read (git
  blob SHA match) — shown as a diff with **Approve & save** / **Reject**.
- **Out of date**: the note changed on the phone, is missing, or (for a new
  note) the name is taken — only **Reject** is offered; ask the AI again
  after syncing.
- **Already applied** / **invalid**: can be removed from the list.

Approving writes the note through the normal note repository (conflict
check, previous version kept in history, creates never overwrite); the
change reaches GitHub with the next **Sync now**. Approving or rejecting
removes the proposal file on GitHub with one commit (the only delete Emerald
performs, and only inside `.emerald/proposals/`). Notes on GitHub are never
written by the inbox.

## Limitations

- Manual sync only; one commit per changed file (large first syncs create
  many commits and count against GitHub's REST API rate limit; Emerald stops
  and reports when the limit is hit).
- Repositories whose tree exceeds GitHub's recursive listing limit are refused.
- Case-only renames and renames in general appear as a new file plus a kept
  old file (nothing is deleted).
- No merge UI: conflicts are resolved by editing the note and its conflict copy.
## How this was tested

- Automated: unit/widget tests against an in-memory fake of the documented
  GitHub API (policy table, conflicts, no deletions, concurrent changes,
  corrupted downloads, fatal errors, full UI flow).
- Real GitHub API (October 2026, by the developer agent, on a temporary
  branch of this repository that was deleted afterwards; in-memory vault, not
  a phone): tree listing and 12 blob downloads, file create and update via the
  contents API, a conflict copy, a no-op third sync, a stale-SHA update
  rejected by GitHub, a missing branch reported as not found, and an invalid
  token rejected by `api.github.com` (401). These requests went through the
  agent's authenticated GitHub proxy (same REST API, different host), except
  the invalid-token check which hit `api.github.com` directly.
- Not yet done: a real phone with a real SAF folder (manual checklist in
  docs/TESTING.md, steps 22–28).
