# Testing

| Level | What runs | Where |
| --- | --- | --- |
| Unit + widget tests | `flutter test` (Dart logic, UI flows with an in-memory vault) | CI job "Format, analyze, test, build APK" |
| Release build | `flutter build apk --release` | same CI job; APK uploaded as artifact |
| Emulator smoke test | `flutter test integration_test` on an API 34 emulator: launch, real SAF channel restore, navigation | CI job "Emulator smoke test (API 34)" |
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

Please report the Android version and device model with any failure.
