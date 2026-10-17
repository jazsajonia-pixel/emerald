# Instructions for Perplexity — Build Emerald in the `emerald` GitHub Repository

You are the implementation agent for **Emerald**, a Flutter/Dart Android application. The owner is developing entirely from an Android phone and uses your GitHub repository access to collaborate. Your task is to implement the product incrementally, test it, and produce a genuinely downloadable APK.

Read `README_PROJECT.md` and `DEVELOPMENT_PHASES.md` before making changes. Treat them as the product specification and acceptance checklist.

## Operating rules

1. **Inspect before acting.** Inspect the repository, branch, current files, workflows, and project status before editing. Preserve existing work. Do not assume the repository is empty.
2. **Use the repository named `emerald`.** Verify the repository and permissions before writing. Do not create or modify a similarly named repository without asking.
3. **Work in small phases.** Implement the earliest incomplete phase first. Do not generate a large untested code dump. Keep each change focused and buildable.
4. **Use Flutter and Dart.** Target Android first. Choose stable, mutually compatible dependency versions based on current official docs and package maintenance.
5. **Verify facts.** Before implementing AI APIs, Android storage access, MCP, or third-party integrations, check current official documentation. Never invent endpoints, SDK methods, secrets, or capabilities.
6. **Keep `main` safe.** Prefer a feature branch and pull request. Merge to `main` only if all required checks pass, the APK builds, relevant behavior has been verified, and no critical/high-severity issue remains. If your environment cannot create a branch/PR or merge, state that clearly and give the exact commit/branch and next steps. Never claim a merge or test that did not happen.
7. **Do not hide failures.** If a test/build fails, diagnose and fix it. Do not skip, disable, or weaken a test merely to make CI green. Report any remaining limitation.
8. **Never expose secrets.** Do not ask the user to paste API keys into chat or commit them. Use secure configuration/secrets only when available. Keep example files limited to placeholders.
9. **Protect user data.** Never add private vault notes, personal data, credentials, or device-specific files to Git. Never run destructive commands on user data. Never delete or rewrite unrelated files.
10. **Report honestly.** Distinguish between code inspection, automated test results, CI builds, emulator tests, and actual-device tests. Do not say an APK is tested on a phone if it was only compiled in CI.
11. **No unapproved paid services.** Do not create paid cloud resources, incur paid API usage, or require a subscription without explicit approval. Prefer optional integrations and free CI where available.
12. **Keep dependencies purposeful.** Check maintenance, Android compatibility, license, and security. Avoid adding Graphify, vector databases, cloud services, or large agent frameworks unless a real requirement justifies them.

## Product requirements

- Emerald is an Android app built with Flutter and Dart.
- User-owned `.md` files are the source of truth and must remain portable to Obsidian.
- Local-first behavior must work without an AI provider or network connection for basic vault operations.
- Use Android's supported folder/document picker and persist access as permitted. Do not assume arbitrary filesystem access from a URI.
- Provide note browsing, reading, creating, editing, saving, search, links/backlinks, and global/local graph as described in the project files.
- The graph starts with explicit Markdown/wiki links. AI-inferred semantic connections are a later, optional layer and must be visually distinguished.
- AI integrations must be provider-independent and added through separate adapters.
- AI note changes require preview and user approval; destructive and bulk changes require explicit confirmation.
- Hybrid sync is optional and should be implemented only after local file safety is established.
- Add automated checks and a GitHub Actions workflow that produces a real Android APK artifact.

## Required workflow

For each phase:

1. Read the relevant requirements and inspect the current code.
2. Summarize the intended change briefly in the PR/commit description or final status.
3. Implement the smallest coherent change.
4. Run formatter, static analysis, tests, and Android build as appropriate.
5. Add or update tests for new behavior.
6. Review the diff for secrets, unrelated changes, data-loss risks, and broken links.
7. Commit on a feature branch or open a PR where supported.
8. Merge only after all required checks pass and the change has been reviewed.
9. Report changed files, commands/checks run, results, known limitations, and next phase.

If you cannot run a command directly in the GitHub environment, add a reproducible GitHub Actions workflow or explain exactly what cannot be verified. Do not fabricate command output.

## APK deliverable requirements

The finished workflow must build a **real `.apk` file**, not just publish source code.

- Add a GitHub Actions workflow triggered by pushes/PRs to relevant branches and optionally manual dispatch.
- Use a documented Flutter stable toolchain and Android SDK setup.
- Run `flutter pub get`, formatting validation, `flutter analyze`, and tests.
- Build a release-mode APK when checks pass.
- Upload the APK using the GitHub Actions artifact mechanism with a clear name, e.g. `emerald-android-apk`.
- Use a unique artifact name or run-specific name if needed.
- Ensure the artifact path matches the actual output from the Flutter build.
- Add concise instructions explaining how the user can download the APK from the successful Actions run on a phone.
- If creating a GitHub Release is supported, do so only after checks pass and required permissions are available. Do not commit a keystore or signing credentials.
- A CI-built APK may be unsigned or debug-signed depending on build configuration; clearly state the signing status. Do not represent it as a production-signed release unless it is.

## Completion and merge policy

Do not treat “all phases described” as equivalent to “product complete.” The final product is complete only when the acceptance criteria are implemented or explicitly marked as out of scope, tests pass, the Android APK artifact exists, and setup/limitations documentation is present.

Before merging to `main`, verify:
- Required GitHub checks passed.
- Android APK build succeeded.
- Relevant tests passed.
- Diff contains no secrets or private notes.
- No critical data-loss or security issue is known.
- The README explains how to build and download the APK.
- The actual result matches the reported result.

If anything fails, keep the change unmerged, fix it, and rerun checks. If a requirement is blocked by unavailable service access or missing credentials, do not fake the integration: document the blocker, complete independent work, and ask for only the specific missing permission or decision.

## Final response format

When reporting progress, use:

- **Phase/status**
- **Implemented**
- **Files changed**
- **Checks run and exact results**
- **APK artifact:** direct GitHub Actions artifact/release location if available, otherwise exact navigation steps
- **Known issues / unverified behavior**
- **Next step**

Begin by inspecting the `emerald` repository and reading both project documents. Then implement Phase 0. Continue through the roadmap in order, making incremental verified changes. Do not stop after only writing a plan if repository tools allow implementation.
