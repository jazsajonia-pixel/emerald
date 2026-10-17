import 'dart:convert';

import 'package:emerald/core/ui/state_views.dart';
import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

const _vault = VaultHandle(id: 'memory://vault', name: 'My Vault');

MemoryVaultStorage _storage({bool remembered = true}) => MemoryVaultStorage(
  files: {
    'Welcome.md': '# Welcome\n\nHello **world**.\n',
    'Projects/Emerald.md': 'Build it.',
  },
  vaultToPick: _vault,
  remembered: remembered ? _vault : null,
);

Future<void> _openBrain(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brain'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('choose a vault and see its notes', (tester) async {
    final storage = _storage(remembered: false);
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    expect(find.text('No vault selected'), findsOneWidget);
    await tester.tap(find.text('Choose vault folder'));
    await tester.pumpAndSettle();
    expect(find.text('My Vault'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    // Folders are listed before notes.
    expect(
      tester.getTopLeft(find.text('Projects')).dy,
      lessThan(tester.getTopLeft(find.text('Welcome')).dy),
    );
  });

  testWidgets('browse into a folder and back up', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _openBrain(tester);
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(find.text('Emerald'), findsWidgets);
    await tester.tap(find.byTooltip('Up one folder'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('open, edit, save, close, and reopen a note', (tester) async {
    final storage = _storage();
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    final editor = find.byKey(const Key('note-editor'));
    expect(
      find.descendant(of: editor, matching: find.textContaining('Hello')),
      findsOneWidget,
    );
    await tester.enterText(editor, '# Welcome\n\nEdited on phone.\n');
    await tester.pump();
    expect(find.text('Welcome •'), findsOneWidget);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      utf8.decode(storage.bytesOf('Welcome.md')!),
      '# Welcome\n\nEdited on phone.\n',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Edited on phone.'), findsOneWidget);
  });

  testWidgets('preview renders Markdown', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _openBrain(tester);
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-editor')), findsNothing);
    expect(find.textContaining('Hello', findRichText: true), findsWidgets);
  });

  testWidgets('create a new note', (tester) async {
    final storage = _storage();
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Shopping list');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(storage.bytesOf('Shopping list.md'), isNotNull);
    expect(find.byKey(const Key('note-editor')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Shopping list'), findsOneWidget);
  });

  testWidgets('duplicate note name is refused without overwriting', (
    tester,
  ) async {
    final storage = _storage();
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Welcome');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('A note with that name already exists.'), findsOneWidget);
    expect(
      utf8.decode(storage.bytesOf('Welcome.md')!),
      startsWith('# Welcome'),
    );
  });

  testWidgets('external change produces a conflict dialog; copy keeps both', (
    tester,
  ) async {
    final storage = _storage();
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-editor')), 'mine');
    await tester.pump();
    storage.setFile('Welcome.md', 'theirs');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Note changed outside Emerald'), findsOneWidget);
    await tester.tap(find.text('Save mine as a copy'));
    await tester.pumpAndSettle();
    expect(utf8.decode(storage.bytesOf('Welcome.md')!), 'theirs');
    final copies = (await storage.listTree(_vault))
        .where((e) => e.path.startsWith('Welcome (conflict'))
        .toList();
    expect(copies, hasLength(1));
    expect(utf8.decode(storage.bytesOf(copies.single.path)!), 'mine');
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    final storage = _storage();
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-editor')), 'draft');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-editor')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(utf8.decode(storage.bytesOf('Welcome.md')!), 'draft');
    expect(find.byKey(const Key('note-editor')), findsNothing);
  });

  testWidgets('revoked access shows the permission-denied state', (
    tester,
  ) async {
    final storage = _storage()..accessRevoked = true;
    await pumpEmerald(tester, storage: storage);
    await _openBrain(tester);
    expect(find.byType(PermissionDeniedView), findsOneWidget);
    await tester.tap(find.text('Choose folder again'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('empty vault shows an empty state', (tester) async {
    await pumpEmerald(
      tester,
      storage: MemoryVaultStorage(vaultToPick: _vault, remembered: _vault),
    );
    await _openBrain(tester);
    expect(find.text('This vault has no notes yet'), findsOneWidget);
  });
}
