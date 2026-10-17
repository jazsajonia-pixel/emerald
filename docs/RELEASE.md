# Release, signing, installation and upgrades (Phase 8)

## What a CI build is

Every push to `main` and every pull request runs **Android CI**: format check,
`flutter analyze`, all unit/widget tests, a release-mode APK build, and an
emulator job (API 34) that runs the on-device tests in `integration_test/`.
The APK is uploaded as the `emerald-android-apk` artifact (30 days) together
with its SHA-256 checksum. The run's summary page states how the APK was signed.

- Version name: from `pubspec.yaml` (currently `0.9.0`, a pre-release: not yet
  tested on a real phone).
- Version code: the number of commits up to the built commit (same in CI
  and Release builds), so later builds can upgrade earlier ones **when signed
  with the same key**.

## Publishing a GitHub Release

The **Release APK** workflow (`.github/workflows/release.yml`) runs when a tag
`v<version>` is pushed. It checks that the tag matches `version:` in
`pubspec.yaml` and is on `main`, runs analyze and tests, builds and signs the
APK (release key if the secrets are set, otherwise a debug key), and publishes
a GitHub Release with `emerald-<version>.apk` and its `.sha256`. The release
notes state the signing and testing status. Versions below 1.0.0 are marked
as pre-releases.

```sh
git checkout main && git pull
git tag v0.9.0 && git push origin v0.9.0
```

Release downloads do not expire (unlike CI artifacts, kept 30 days) and do
not require signing in to GitHub.

## Signing

| Situation | Signing | Upgrades |
| --- | --- | --- |
| Default (no secrets configured) | Debug key generated on the CI runner (`CN=Android Debug`) | Usually **fail** between builds from different runs — uninstall first |
| Release keystore configured as GitHub secrets | Your own stable key | Work normally (install over the old version) |

No keystore, password, or signing credential is stored in the repository.

### Configure a stable release key (optional, owner action)

1. On a computer with a JDK, create a keystore and keep it safe (losing it
   means future builds can no longer upgrade installed copies):
   ```sh
   keytool -genkeypair -keystore emerald-release.jks -alias emerald \
     -keyalg RSA -keysize 4096 -validity 10000
   ```
2. Base64-encode it: `base64 -w0 emerald-release.jks > keystore.txt`
   (macOS: `base64 -i emerald-release.jks -o keystore.txt`).
3. GitHub → repository **Settings → Secrets and variables → Actions → New
   repository secret**, add:
   - `EMERALD_KEYSTORE_BASE64` — contents of `keystore.txt`
   - `EMERALD_KEYSTORE_PASSWORD`
   - `EMERALD_KEY_ALIAS` — e.g. `emerald`
   - `EMERALD_KEY_PASSWORD`
4. Re-run Android CI. The run summary then shows "Signed with the configured
   release key". Secrets are not available to pull requests from forks, so
   those builds stay debug-signed.

Locally, the same environment variables (`EMERALD_KEYSTORE_PATH` pointing to
the `.jks` file, plus the three above) produce a release-signed APK; without
them `flutter build apk --release` uses your local debug key.

Moving from debug-signed builds to the release key requires one uninstall,
because Android does not allow a signature change in place.

## Installing on a phone

See the README section "Download the APK on your phone". Android asks you to
allow "Install unknown apps" for the browser or file manager you use; grant
it only to that app, and you can turn it off again afterwards. Play Protect
may warn about an app from an unknown developer; this is expected for an APK
that is not distributed through Google Play.

Before installing, you can compare the APK's SHA-256 with the
`app-release.apk.sha256` file and the value printed in the CI log.

## Permissions

| Permission | Why |
| --- | --- |
| `INTERNET` | Only for optional AI requests and optional GitHub sync that you configure and start. |
| Folder access (Storage Access Framework) | Granted by you for the one vault folder you pick; no broad storage permission is requested. |

Not requested: contacts, location, camera, microphone, notifications,
`MANAGE_EXTERNAL_STORAGE`. Android auto-backup is disabled for app data
(`allowBackup="false"`), so stored API keys/tokens are not copied to cloud
backups. Plain HTTP is blocked except to `localhost`.

## Upgrades and uninstalling

- Your notes live in your vault folder, not inside the app. Uninstalling
  Emerald never deletes them.
- Uninstalling deletes app data: the remembered vault (you pick it again),
  note history, AI keys, the GitHub token and sync history. After reinstalling,
  the first GitHub sync is conservative: files that differ become conflict
  copies; nothing is deleted.
- Data formats inside the app (settings keys, history files, sync state) are
  read backwards-compatibly; no migration step is required between the
  builds in this repository.

## Release checklist

1. All CI checks green on `main` (both jobs).
2. Manual device checklist in docs/TESTING.md completed on a real phone, with
   results recorded in docs/STATUS.md.
3. Decide signing (stable key strongly recommended before sharing builds).
4. Bump `version:` in `pubspec.yaml` (via a PR), then push the matching tag
   to publish a GitHub Release.
