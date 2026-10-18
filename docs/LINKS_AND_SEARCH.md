# Links, backlinks and search

## Supported link syntax

| Syntax | Example | Notes |
| --- | --- | --- |
| Wiki link | `[[Note]]` | Matched by note title (file name without `.md`), case-insensitive |
| Wiki link with folder | `[[Folder/Note]]` | Matches a path ending in `Folder/Note.md` |
| Alias | `[[Note\|shown text]]` | Escaped `\|` inside tables is handled |
| Heading / block | `[[Note#Heading]]`, `[[Note#^id]]` | Links to the note; the heading is not scrolled to yet |
| Embed | `![[Note]]` | Counted as a link; content is not embedded in the preview |
| Markdown link | `[text](Other.md)`, `[t](../Folder/Note%20Two.md)`, `[t](<With Space.md>)` | Relative to the linking note; `/x.md` is relative to the vault root; extension optional |

Not counted as note links: images, external URLs (`https:`, `mailto:`,
`obsidian:` …), same-note anchors (`#x`, `[[#x]]`), attachments (`.pdf`,
`.png` …), and anything inside fenced code blocks or inline code.

## Resolution rules

- Links are matched only against notes found in the vault listing. Resolution
  never opens a path, so a link cannot reach outside the vault; links that
  climb above the vault root (`../..`) are reported as **outside vault**.
- **Duplicate names** (`A/Plan.md`, `B/Plan.md`): `[[Plan]]` prefers an exact
  case match, then the linking note's folder, then the shallowest path, then
  alphabetical order. Such links are flagged as ambiguous in the links sheet.
  Use `[[A/Plan]]` to be explicit.
- Unmatched links are **broken**. Renaming or deleting a note outside Sapphire
  turns its incoming links into broken links after the next rescan.
- External links in the preview are never opened automatically; Sapphire
  shows the URL and offers to copy it.

## The index

- Built in memory from the Markdown files whenever a vault is opened, and
  updated incrementally: only files whose size or modification time changed
  are re-read on **Rescan**. Notes saved in Sapphire update immediately.
- **Rebuild index** (Brain → ⋮) discards the index and re-reads every note.
  Indexing only reads files; it never writes, moves or deletes notes.
- Files that cannot be read (e.g. larger than 8 MB) are listed under
  *Unlinked notes → Could not index*.

**Deviation from the original plan:** the project overview suggested a SQLite
metadata database. The index is currently in memory and rebuilt on each app
start, which keeps the vault the only source of truth and avoids a database
dependency. If start-up indexing proves too slow on large vaults, a
regenerable on-device cache can be added later without changing behaviour.

## Search

Case-insensitive substring search over titles, folder names and note text.
Every space-separated term must match. Results are ranked: exact title, title
match, title prefix, then number of matches in the text.
Not supported yet: fuzzy matching, accent-insensitive matching, tags/front
matter filters.
