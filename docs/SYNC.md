# GitHub sync

Optional, off until you connect GitHub. Sapphire works fully offline without it.

Sapphire keeps your phone's notes folder and **one branch of one GitHub
repository** identical — like GitSync, but for Markdown notes. Requests go
directly from the phone to GitHub; there is no Sapphire server and no MCP
server. Any AI that can read and write your notes repository (ChatGPT,
Claude, Perplexity, Codex, …) sees exactly what is on your phone, and its
changes show up on the phone at the next sync.

## Connect (Sign in with GitHub)

Sapphire uses GitHub's **device flow** with a small, private **GitHub App**
that you own. Only the app's public Client ID is needed — no password, no
client secret and no personal token is stored in the APK. GitHub only lets the
app reach repositories you install it on, so choosing "Only select
repositories → sapphire-knowledge" limits Sapphire to your notes repository.

One-time setup (Settings → GitHub sync → "One-time setup"):

1. **Create the GitHub App** – the button opens GitHub's "New GitHub App" page
   pre-filled (name, no webhook, *Contents: Read and write*). Tick **Enable
   Device Flow** and press **Create GitHub App**.
2. Copy the app's **Client ID** into Sapphire. (Or set the repository variable
   `SAPPHIRE_GITHUB_CLIENT_ID`; CI then bakes it into the APK so the field is
   pre-filled.)
3. **Install App** → your account → **Only select repositories** → your notes
   repository.

Then tap **Sign in with GitHub**: Sapphire shows a code, **Copy code & open
GitHub** opens github.com/login/device, you paste the code and approve.
Sapphire lists the repositories the app is installed on; tap your notes
repository. Sync is turned on and the first sync starts immediately.

Tokens: GitHub user tokens expire after 8 hours and are refreshed
automatically with the refresh token (valid 6 months; signing in again
renews it). Both live in Android Keystore-backed secure storage.

**Advanced:** "Use a personal access token instead" still accepts a
fine-grained personal access token (Contents: Read and write on one
repository) if you prefer not to create a GitHub App.

## When it syncs

With **Sync automatically** on (default):

- when the app opens and whenever you come back to it;
- about 3 seconds after Sapphire detects a note change (debounced);
- when you open the app or return to it, which also checks for remote GitHub changes.

There is no repeating schedule. The setting can be switched off at any time;
use **Sync now** when you want an immediate manual check. Notes changed by the
latest successful sync are highlighted in mint in the graph.

**Sync now** is always available. Android does not let Sapphire run while it
is fully closed, so changes made on GitHub while the app is closed arrive the
next time you open it.

## What is synced

- All `.md` files in the vault, in the same folder structure (repository root
  = vault root).
- Not synced: hidden files/folders (e.g. `.obsidian/`, `.git/`), non-Markdown
  files, files over 8 MB (listed as notices).

## Conflict and deletion policy

Sapphire compares three Git blob hashes per file: on the phone, on GitHub, and
at the last successful sync (stored in app-private storage, not in the vault).

| Phone | GitHub | Result |
| --- | --- | --- |
| changed | unchanged | upload (one commit per file) |
| unchanged | changed | download; the old local version goes to note history |
| changed | changed (differently) | **conflict**: GitHub's version is saved as `Title (GitHub conflict YYYY-MM-DD HHMM).md` next to your note; your note is untouched |
| new | absent | upload |
| absent | new | download (folders created as needed) |
| deleted | unchanged | **deleted on GitHub** (with *Mirror deletions*, default) — otherwise kept on GitHub |
| unchanged | deleted | **deleted on the phone**, after saving its content to note history (with *Mirror deletions*) — otherwise kept |
| deleted | changed | restored from GitHub (an edit beats a deletion) |
| changed | deleted | re-uploaded (an edit beats a deletion) |

Safety brake: if one sync would delete more than half of the synced notes
(and more than 5), or the phone folder suddenly looks empty, **nothing is
deleted** and a notice explains why — that pattern usually means lost folder
access or a wrong repository, not a real clean-up.

Every local overwrite or delete re-reads the file and is refused if it changed
since the comparison; every GitHub update/delete sends the expected blob SHA
and GitHub refuses it (409) if the file changed meanwhile. Refused files are
retried on the next sync — nothing is lost. Downloaded content is verified
against its Git blob hash before it is written.

A public repository is refused unless you turn on "Allow a public repository"
and confirm, because every synced note would be readable by anyone.

## Where data goes

- Note content: your phone and the GitHub repository (GitHub's terms apply).
  Commit messages contain the note path, e.g. `Update Projects/Plan.md
  (Sapphire sync)`.
- Tokens: Android Keystore-backed secure storage; never written to the vault,
  never displayed, logged or included in error messages (tested). **Sign out
  and remove sync** deletes them and the sync history without touching notes
  or the repository. You can also revoke access on GitHub (Settings →
  Applications) at any time.
- Sync history (hashes, sizes, times — no note content): app-private storage.

## Verified API facts (October 2026)

| Endpoint / fact | Source |
| --- | --- |
| `PUT /repos/{owner}/{repo}/contents/{path}` (message, base64 content, `sha` when updating, branch; 200/201/404/409/422; Contents: write; must be used serially) | https://docs.github.com/en/rest/repos/contents |
| `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1` (`truncated`; 100,000 entries / 7 MB limit; Contents: read) | https://docs.github.com/en/rest/git/trees |
| `GET /repos/{owner}/{repo}/git/blobs/{sha}` (base64 content, up to 100 MB; Contents: read) | https://docs.github.com/en/rest/git/blobs |
| `GET /repos/{owner}/{repo}` (`private`, `permissions.push`; Metadata: read) | https://docs.github.com/en/rest/repos/repos#get-a-repository |
| `X-GitHub-Api-Version: 2022-11-28` supported until 2028-03-10 | https://docs.github.com/en/rest/about-the-rest-api/api-versions |
| `DELETE /repos/{owner}/{repo}/contents/{path}` (message, `sha`, branch; 409 if changed) | https://docs.github.com/en/rest/repos/contents#delete-a-file |
| Device flow: `POST github.com/login/device/code`, poll `POST github.com/login/oauth/access_token` (`authorization_pending`, `slow_down`, `expired_token`, `access_denied`); no client secret | https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app |
| Refresh: `grant_type=refresh_token`; `client_secret` not required for device-flow tokens; access tokens expire after 8 h | https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens |
| Pre-filled app registration (`name`, `url`, `public`, `webhook_active`, `contents=write`) | https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-using-url-parameters |
| `GET /user/installations`, `GET /user/installations/{id}/repositories` | https://docs.github.com/en/rest/apps/installations |
| Fine-grained token creation steps | https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens |

Not documented on those pages and therefore handled defensively: GitHub's
response for an empty repository's tree (Sapphire treats `409` there as
"empty repository" and stops without changes).
