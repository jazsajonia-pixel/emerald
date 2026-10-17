# Emerald

Emerald is a local-first Android app for working with a vault of ordinary
Markdown (`.md`) files — browse, edit, search, follow links and backlinks, and
explore a knowledge graph. Your Markdown files remain the source of truth and
stay compatible with Obsidian and other editors.

- Product specification: [`README_PROJECT.md`](README_PROJECT.md)
- Roadmap and acceptance criteria: [`DEVELOPMENT_PHASES.md`](DEVELOPMENT_PHASES.md)
- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Status of each phase: [`docs/STATUS.md`](docs/STATUS.md)

## Project facts

| Item | Value |
| --- | --- |
| Platform | Android (Flutter + Dart) |
| Application ID | `io.github.jazsajonia.emerald` |
| Flutter toolchain (CI) | 3.47.7 stable (Dart 3.13.5) |
| Java (CI) | Temurin 17 |
| License | Not chosen yet — see [`LICENSE_DECISION.md`](LICENSE_DECISION.md) |

## Download the APK on your phone

Every push and pull request runs the **Android CI** workflow. When it succeeds
it uploads an artifact called `emerald-android-apk`.

1. Open the repository on GitHub in your phone browser (desktop mode helps if
   the Actions page is hard to use in the mobile layout), and sign in.
2. Tap **Actions** → **Android CI**.
3. Open the most recent run with a green check mark (for `main`, or for the
   branch/PR you want to try).
4. Scroll to **Artifacts** and tap **emerald-android-apk**. GitHub downloads a
   `.zip` file (you must be signed in to download artifacts).
5. Open the zip with your file manager and extract `app-release.apk`.
   `app-release.apk.sha256` contains the checksum printed in the CI log.
6. Tap the APK to install. Android will ask you to allow installs from that
   app ("Install unknown apps"); allow it only for the app you are using.

Artifacts are kept for 30 days.

### Signing status

The CI APK is a **release-mode build signed with the Android debug key**
generated on the CI runner. It is fine for personal testing but it is **not a
production-signed release**. Because every runner may generate a different
debug key, Android may refuse to install a newer CI APK over an older one
("App not installed" / signature conflict). If that happens, uninstall Emerald
first — your notes live in your own vault folder and are not deleted by
uninstalling, but app settings (such as the remembered vault) are.

No keystore or signing credentials are stored in this repository.

## Build locally

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

## Privacy and secrets

- Never commit API keys, tokens, signing keys, or personal notes.
- Emerald does not send vault content anywhere unless you explicitly configure
  and invoke a remote AI integration (planned for a later phase).
