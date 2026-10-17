# Testing

| Level | What runs | Where |
| --- | --- | --- |
| Unit + widget tests | `flutter test` (Dart logic, UI flows with an in-memory vault) | CI job "Format, analyze, test, build APK" |
| Release build | `flutter build apk --release` | same CI job; APK uploaded as artifact |
| Emulator tests | `flutter test integration_test` on an API 34 emulator: launch, real SAF channel restore, navigation; create/link/save/reopen/search/backlinks/graph flow (in-memory vault); Android Keystore secure storage; app-private history and sync-state files through the real Kotlin channel | CI job "Emulator smoke test (API 34)" |
| Real device | Manual checklist below | Owner's phone |

The emulator test cannot operate the system folder picker, so choosing a
folder and reading/writing real files through SAF must be checked manually.

## Manual device checklist

Install the APK from the latest successful run, then:

1. Open **Brain** → **Choose vault folder** → create/select e.g.
   `Documents/EmeraldTest`. Notes in it appear (folders first).
2. **New note** "Test" → type text → **Save** → "Saved" appears.
3. Back out, reopen "Test": the text is there.
4. Force-stop Emerald, reopen: the vault is still selected (persisted access).
5. Open the same file in another editor (e.g. Obsidian on the same folder):
   the saved text is visible.
6. Open "Test" in Emerald, edit without saving, change the file in the other
   editor, return and tap **Save** → conflict dialog. Try *Save mine as a
   copy*; both files exist.
7. ⋮ → **Previous versions** lists earlier saves.
8. Settings → **Forget vault** → Brain shows "No vault selected"; files remain.
9. Try creating a note with an existing name → refused, original unchanged.

10. Write `[[Test]]` in another note, save, open "Test" → ⋮ → *Links and
    backlinks* shows it. In preview, tapping the link opens the note.
11. Brain → search icon → search a word from a note; it is found.
12. Edit a note in another app, return, tap **Rescan**; search finds the new
    text.
13. Graph tab: dots and lines appear; pinch/drag work; tapping a dot opens
    its note; long-press shows its local graph.

AI (optional; needs your own Gemini key — the free tier is enough):

14. Settings → **AI provider** → paste key → **Test connection** → models are
    listed. A wrong key shows "The API key was rejected…".
15. **Save** → the key field is cleared and the key is never shown again.
16. AI Hub → ask "What notes mention X?" → consent dialog → **I understand** →
    an answer appears with "Searched…/Read…" lines and "Sent to …" banner.
17. Ask "Add a summary line to note Test" → a proposal card with a diff. Tap
    **Reject** → the file is unchanged. Repeat and **Approve & save** → the
    change is in the file (check in another app); ⋮ → Previous versions shows
    the pre-AI version.
18. Turn on airplane mode and ask again → a network error, notes unchanged.
19. OpenAI-compatible with OpenAI: provider **OpenAI-compatible**, base URL
    `https://api.openai.com/v1`, your key, model `gpt-6-luna`, reasoning
    effort `none` → Test connection → ask a question about a note (paid).
20. OpenAI-compatible with local Ollama (e.g. Termux): base URL
    `http://localhost:11434/v1`, no key, a tool-capable model → ask a
    question. Entering `http://<another-ip>` is refused.
21. Switch back to Gemini in settings → its saved key/model are still there;
    notes are unchanged.

GitHub sync (optional; needs a private repo with a README and a fine-grained
token — see docs/SYNC.md):

22. Settings → **GitHub sync** → fill in → **Test connection** → "Connected to a
    private repository…". Save; the token is not shown again.
23. Enable → **Sync now** → notes appear in the repository on github.com, one
    commit per file.
24. Edit a note on github.com, Sync now → the change is on the phone; ⋮ →
    Previous versions shows the old text.
25. Edit the same note on the phone and on github.com differently, Sync now →
    a "(GitHub conflict …)" note appears; your phone version is unchanged.
26. Delete a note on github.com, Sync now → it is still on the phone.
27. Airplane mode → Sync now → "No connection to GitHub", nothing changed.
28. Revoke the token on GitHub → Sync now → "GitHub rejected the token".

Please report the Android version and device model with any failure.
