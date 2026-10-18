// On-device flow tests. Run on an Android emulator in CI. The vault itself is
// in memory (the system folder picker cannot be automated), but everything
// else is the real Android runtime: rendering, gestures, dart:io in the app's
// private directory (via the real Kotlin channel), and Android Keystore-backed
// secure storage.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:emerald/app/app.dart';
import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/saf_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:emerald/features/ai/ai_config.dart';
import 'package:emerald/features/notes/note_history.dart';
import 'package:emerald/features/sync/sync_state_store.dart';
import 'package:emerald/features/vault/vault_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _vault = VaultHandle(id: 'memory://device-vault', name: 'Device Vault');

/// Taps a top-level destination (bottom bar on phones, rail on wide screens).
Future<void> _nav(WidgetTester tester, String label) async {
  final bar = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  final rail = find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
  await tester.tap(bar.evaluate().isNotEmpty ? bar : rail);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create, link, save, reopen, search, backlinks, graph', (
    tester,
  ) async {
    final storage = MemoryVaultStorage(
      files: {'Garden.md': '# Garden\n\nStart here.\n'},
      vaultToPick: _vault,
      remembered: _vault,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
        ],
        child: const EmeraldApp(reduceMotion: true),
      ),
    );
    await tester.pumpAndSettle();
    await _nav(tester, 'Brain');
    expect(find.text('Garden'), findsOneWidget);

    // Create a note that links to Garden.
    await _tap(tester, find.text('New note'));
    await tester.enterText(find.byType(TextField), 'Device note');
    await _tap(tester, find.text('Create'));
    await tester.enterText(
      find.byKey(const Key('note-editor')),
      'Written on Android. See [[Garden]].\n',
    );
    await tester.pump();
    await _tap(tester, find.byTooltip('Save'));
    expect(
      utf8.decode(storage.bytesOf('Device note.md')!),
      'Written on Android. See [[Garden]].\n',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Reopen.
    await _tap(tester, find.text('Device note'));
    expect(find.textContaining('Written on Android.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Search.
    await _tap(tester, find.byTooltip('Search'));
    await tester.enterText(find.byKey(const Key('search-field')), 'android');
    await tester.pumpAndSettle();
    expect(find.text('Device note'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Backlinks of Garden include the new note.
    await _tap(tester, find.text('Garden'));
    await _tap(tester, find.byTooltip('Note actions').last);
    await _tap(tester, find.text('Links and backlinks'));
    expect(find.text('Backlinks (1)'), findsOneWidget);
    expect(find.text('Device note.md'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // dismiss sheet
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Graph shows both notes and the link.
    await _nav(tester, 'Graph');
    expect(find.text('2 notes · 1 links'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Keystore-backed secure storage works on device', (tester) async {
    final store = SecureSecretStore();
    const key = 'emerald.integration.check';
    await store.write(key, 'value-1');
    expect(await store.read(key), 'value-1');
    await store.delete(key);
    expect(await store.read(key), isNull);
  });

  testWidgets('app-private history and sync state work via the real channel', (
    tester,
  ) async {
    final dir = Directory(await SafVaultStorage().appFilesDir());
    expect(await dir.exists(), isTrue);

    final history = FileNoteHistory(() async => dir, maxPerNote: 2);
    for (var i = 0; i < 3; i++) {
      await history.record(
        'it-vault',
        'Note.md',
        Uint8List.fromList(utf8.encode('v$i')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final entries = await history.list('it-vault', 'Note.md');
    expect(entries, hasLength(2));
    expect(await entries.first.file.readAsString(), 'v2');

    final sync = FileSyncStateStore(() async => dir);
    final when = DateTime.utc(2026, 10, 18, 1, 2, 3);
    await sync.save(
      'it-scope',
      SyncBase({
        'a.md': const SyncedFile(sha: 'abc', size: 3, lastModified: 9),
      }, lastSync: when),
    );
    final loaded = await sync.load('it-scope');
    expect(loaded.files['a.md']!.sha, 'abc');
    expect(loaded.lastSync, when);
    await sync.clear('it-scope');
    expect((await sync.load('it-scope')).files, isEmpty);
  });
}
