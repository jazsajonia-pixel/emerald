import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:emerald/features/ai/ai_config.dart';
import 'package:emerald/features/sync/github_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import 'fake_github.dart';

const _vault = VaultHandle(id: 'memory://vault', name: 'My Vault');
const _token = 'github_pat_SECRET_123';

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openSync(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Settings'),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.text('GitHub sync'));
}

void main() {
  late FakeGitHub gh;

  Future<MemorySecretStore> setUpApp(
    WidgetTester tester, {
    bool private = true,
  }) async {
    gh = FakeGitHub(files: {'Remote.md': 'from github'}, isPrivate: private);
    final secrets = MemorySecretStore();
    await pumpEmerald(
      tester,
      storage: MemoryVaultStorage(
        files: {'Local.md': 'from phone'},
        remembered: _vault,
      ),
      secrets: secrets,
      gitHubFactory: (t, o, r) =>
          GitHubClient(token: t, owner: o, repo: r, client: gh.mock),
    );
    return secrets;
  }

  Future<void> fillAndSave(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('sync-owner')), 'me');
    await tester.enterText(find.byKey(const Key('sync-repo')), 'notes');
    await tester.enterText(find.byKey(const Key('sync-token')), _token);
    await _tap(tester, find.text('Save settings'));
  }

  testWidgets('set up, enable and sync with a private repository', (
    tester,
  ) async {
    final secrets = await setUpApp(tester);
    await _openSync(tester);
    expect(find.text('Sync is off.'), findsOneWidget);

    await fillAndSave(tester);
    expect(secrets.values['sync.github.token'], _token);
    expect(find.textContaining(_token), findsNothing);
    expect(find.text('Token (saved — enter to replace)'), findsOneWidget);

    await _tap(tester, find.text('Test connection'));
    expect(
      find.textContaining('private repository with write access'),
      findsOneWidget,
    );

    // Sync now is disabled until sync is enabled.
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('sync-now'))).onPressed,
      isNull,
    );
    await _tap(tester, find.byKey(const Key('sync-enabled')));
    await _tap(tester, find.byKey(const Key('sync-now')));
    expect(find.textContaining('Uploaded 1 · Downloaded 1'), findsOneWidget);
    expect(gh.text('Local.md'), 'from phone');
    expect(find.textContaining('Last successful sync'), findsOneWidget);

    // Downloaded note appears in Brain after the automatic rescan.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Brain'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remote'), findsOneWidget);
  });

  testWidgets('public repositories are refused unless explicitly allowed', (
    tester,
  ) async {
    await setUpApp(tester, private: false);
    await _openSync(tester);
    await fillAndSave(tester);
    await _tap(tester, find.byKey(const Key('sync-enabled')));
    await _tap(tester, find.byKey(const Key('sync-now')));
    expect(find.textContaining('This repository is PUBLIC'), findsOneWidget);
    expect(gh.requests.where((r) => r.method == 'PUT'), isEmpty);

    await _tap(tester, find.text('Allow a public repository'));
    expect(find.text('Sync to a public repository?'), findsOneWidget);
    await _tap(tester, find.text('Allow public'));
    await _tap(tester, find.byKey(const Key('sync-now')));
    expect(gh.text('Local.md'), 'from phone');
  });

  testWidgets('remove deletes the token but no notes', (tester) async {
    final secrets = await setUpApp(tester);
    await _openSync(tester);
    await fillAndSave(tester);
    await _tap(tester, find.text('Remove'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Remove'));
    expect(secrets.values.keys.where((k) => k.startsWith('sync.')), isEmpty);
    expect(gh.text('Remote.md'), 'from github');
  });

  testWidgets('bad token shows a plain-language error', (tester) async {
    await setUpApp(tester);
    gh.failStatus = 401;
    await _openSync(tester);
    await fillAndSave(tester);
    await _tap(tester, find.text('Test connection'));
    expect(
      find.text(SyncException(SyncErrorCode.unauthorized).userMessage),
      findsOneWidget,
    );
  });
}
