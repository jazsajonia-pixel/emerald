# Sapphire

<img src="docs/assets/sapphire-icon-512.png" alt="Sapphire logo" width="96" />

Sapphire is a local-first Android app for working with a vault of ordinary
Markdown (`.md`) files — browse, edit, search, follow links and backlinks, and
explore a knowledge graph. Your Markdown files remain the source of truth and
stay compatible with Obsidian and other editors.

- Product specification: [`README_PROJECT.md`](README_PROJECT.md)
- Roadmap and acceptance criteria: [`DEVELOPMENT_PHASES.md`](DEVELOPMENT_PHASES.md)
- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Status of each phase: [`docs/STATUS.md`](docs/STATUS.md)
- Vault storage, safety and limitations: [`docs/STORAGE.md`](docs/STORAGE.md)
- Links, backlinks and search: [`docs/LINKS_AND_SEARCH.md`](docs/LINKS_AND_SEARCH.md)
- Graph: [`docs/GRAPH.md`](docs/GRAPH.md)
- AI (optional, bring your own key): [`docs/AI.md`](docs/AI.md)
- GitHub sync — sign in with GitHub, automatic two-way sync: [`docs/SYNC.md`](docs/SYNC.md)
- Release, signing, permissions, upgrades: [`docs/RELEASE.md`](docs/RELEASE.md)
- Use your notes from any AI: give it your notes repository; it reads `AGENTS.md` first ([`docs/AI.md`](docs/AI.md))
- Testing levels and manual device checklist: [`docs/TESTING.md`](docs/TESTING.md)

## Project facts

| Item | Value |
| --- | --- |
| Platform | Android (Flutter + Dart) |
| Application ID | `io.github.jazsajonia.sapphire` |
| Flutter toolchain (CI) | 3.47.7 stable (Dart 3.13.5) |
| Java (CI) | Temurin 17 |
| License | Not chosen yet — see [`LICENSE_DECISION.md`](LICENSE_DECISION.md) |

## Download the APK on your phone

**Easiest:** open the repository's **Releases** page on your phone, download
the latest `sapphire-<version>.apk`, and open it. No GitHub sign-in needed.

### From CI (latest build of any branch)

Every push and pull request runs the **Android CI** workflow. When it succeeds
it uploads an artifact called `sapphire-android-apk`.

1. Open the repository on GitHub in your phone browser (desktop mode helps if
   the Actions page is hard to use in the mobile layout), and sign in.
2. Tap **Actions** → **Android CI**.
3. Open the most recent run with a green check mark (for `main`, or for the
   branch/PR you want to try).
4. Scroll to **Artifacts** and tap **sapphire-android-apk**. GitHub downloads a
   `.zip` file (you must be signed in to download artifacts).
5. Open the zip with your file manager and extract `app-release.apk`.
   `app-release.apk.sha256` contains the checksum printed in the CI log.
6. Tap the APK to install. Android will ask you to allow installs from that
   app ("Install unknown apps"); allow it only for the app you are using.

Artifacts are kept for 30 days.

### Signing status

Unless the repository owner configures a release keystore as GitHub secrets
(see [`docs/RELEASE.md`](docs/RELEASE.md)), the CI APK is a **release-mode
build signed with the Android debug key** generated on the CI runner. It is
fine for personal testing but it is **not a production-signed release**. The
CI run summary states which key was used. Because every runner may generate a
different debug key, Android may refuse to install a newer CI APK over an
older one ("App not installed" / signature conflict). If that happens,
uninstall Sapphire first — your notes live in your own vault folder and are not
deleted by uninstalling, but app settings (remembered vault, AI keys, GitHub
token) are.

No keystore or signing credentials are stored in this repository.

Permissions, upgrades, and the release checklist: [`docs/RELEASE.md`](docs/RELEASE.md).

## Build locally

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build apk --release
# on-device tests (needs a running emulator or connected phone):
flutter test integration_test
# output: build/app/outputs/flutter-apk/app-release.apk
```

## Privacy and secrets

- Never commit API keys, tokens, signing keys, or personal notes.
- Sapphire does not send vault content anywhere unless you explicitly configure
  a remote AI provider with your own key and send a question. See
  [`docs/AI.md`](docs/AI.md) for exactly what is sent and how keys are stored.
- Optional GitHub sync sends notes only to the private repository you
  choose and keeps both sides identical, including deletions (with a safety
  brake and note history) ([`docs/SYNC.md`](docs/SYNC.md)).
- AI can only *propose* note changes; nothing is written until you approve it,
  and there is no AI delete tool.
