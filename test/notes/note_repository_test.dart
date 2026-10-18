import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/data/vault_storage.dart';
import 'package:sapphire/features/notes/note_history.dart';
import 'package:sapphire/features/notes/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher throwsVault(VaultErrorCode code) =>
    throwsA(isA<VaultException>().having((e) => e.code, 'code', code));

void main() {
  late MemoryVaultStorage storage;
  late NoteRepository repo;
  late Directory tmp;
  late FileNoteHistory history;
  const vault = VaultHandle(id: 'memory://vault', name: 'Vault');

  setUp(() async {
    storage = MemoryVaultStorage(
      files: {'Inbox/Idea.md': '# Idea\n', 'Readme.md': 'hello'},
      remembered: vault,
    );
    tmp = await Directory.systemTemp.createTemp('sapphire_history');
    history = FileNoteHistory(() async => tmp, maxPerNote: 3);
    repo = NoteRepository(storage, history);
  });

  tearDown(() => tmp.delete(recursive: true));

  String content(String path) => utf8.decode(storage.bytesOf(path)!);

  test('open, edit, save, reopen', () async {
    final doc = await repo.open(vault, 'Inbox/Idea.md');
    expect(doc.text, '# Idea\n');
    final saved = await repo.save(vault, doc, '# Idea\n\nMore.\n');
    expect(content('Inbox/Idea.md'), '# Idea\n\nMore.\n');
    final reopened = await repo.open(vault, 'Inbox/Idea.md');
    expect(reopened.text, '# Idea\n\nMore.\n');
    expect(reopened.stamp.sha256, saved.stamp.sha256);
  });

  test('consecutive saves use the updated stamp (no false conflict)', () async {
    var doc = await repo.open(vault, 'Readme.md');
    doc = await repo.save(vault, doc, 'one');
    doc = await repo.save(vault, doc, 'two');
    expect(content('Readme.md'), 'two');
  });

  test('external change is detected and nothing is written', () async {
    final doc = await repo.open(vault, 'Readme.md');
    storage.setFile('Readme.md', 'changed by Obsidian');
    await expectLater(
      repo.save(vault, doc, 'my edit'),
      throwsVault(VaultErrorCode.conflict),
    );
    expect(content('Readme.md'), 'changed by Obsidian');
  });

  test('saveCopy keeps both versions', () async {
    final doc = await repo.open(vault, 'Inbox/Idea.md');
    storage.setFile('Inbox/Idea.md', 'theirs');
    final copy = await repo.saveCopy(
      vault,
      doc,
      'mine',
      now: DateTime(2026, 10, 17, 9, 5),
    );
    expect(copy.path, 'Inbox/Idea (conflict 2026-10-17 0905).md');
    expect(content(copy.path), 'mine');
    expect(content('Inbox/Idea.md'), 'theirs');
    final second = await repo.saveCopy(
      vault,
      doc,
      'mine again',
      now: DateTime(2026, 10, 17, 9, 5),
    );
    expect(second.path, 'Inbox/Idea (conflict 2026-10-17 0905 2).md');
  });

  test(
    'overwrite replaces the external version and keeps it in history',
    () async {
      final doc = await repo.open(vault, 'Readme.md');
      storage.setFile('Readme.md', 'theirs');
      await repo.overwrite(vault, doc, 'mine');
      expect(content('Readme.md'), 'mine');
      final versions = await history.list(vault.id, 'Readme.md');
      expect(
        versions.map((v) => utf8.decode(v.file.readAsBytesSync())),
        contains('theirs'),
      );
    },
  );

  test('history keeps only the most recent versions', () async {
    var doc = await repo.open(vault, 'Readme.md');
    for (var i = 0; i < 5; i++) {
      doc = await repo.save(vault, doc, 'v$i');
    }
    final versions = await history.list(vault.id, 'Readme.md');
    expect(versions, hasLength(3));
    expect(utf8.decode(versions.first.file.readAsBytesSync()), 'v3');
  });

  test('create never overwrites an existing note', () async {
    await expectLater(
      repo.create(vault, '', 'Readme'),
      throwsVault(VaultErrorCode.alreadyExists),
    );
    expect(content('Readme.md'), 'hello');
    final doc = await repo.create(vault, 'Inbox', 'Neue Notiz ✨');
    expect(doc.path, 'Inbox/Neue Notiz ✨.md');
    expect(doc.text, '');
  });

  test('create in a missing folder fails', () async {
    await expectLater(
      repo.create(vault, 'Nope', 'X'),
      throwsVault(VaultErrorCode.notFound),
    );
  });

  test('missing file and deleted-while-open are reported', () async {
    await expectLater(
      repo.open(vault, 'Gone.md'),
      throwsVault(VaultErrorCode.notFound),
    );
    final doc = await repo.open(vault, 'Readme.md');
    storage.deleteExternally('Readme.md');
    await expectLater(
      repo.save(vault, doc, 'x'),
      throwsVault(VaultErrorCode.notFound),
    );
    final re = await repo.recreate(vault, 'Readme.md', 'x');
    expect(re.text, 'x');
  });

  test('path traversal and non-markdown paths are rejected', () async {
    expect(() => repo.open(vault, '../secret.md'), throwsA(anything));
    await expectLater(
      repo.open(vault, 'image.png'),
      throwsVault(VaultErrorCode.invalidPath),
    );
    await expectLater(
      storage.readFile(vault, '../x.md'),
      throwsVault(VaultErrorCode.invalidPath),
    );
  });

  test('revoked permission surfaces as permissionDenied', () async {
    storage.accessRevoked = true;
    await expectLater(
      repo.open(vault, 'Readme.md'),
      throwsVault(VaultErrorCode.permissionDenied),
    );
  });

  test('read-only (invalid UTF-8) notes cannot be saved', () async {
    storage.setBytes('Binary.md', Uint8List.fromList([0x61, 0xFF]));
    final doc = await repo.open(vault, 'Binary.md');
    expect(doc.readOnly, isTrue);
    await expectLater(
      repo.save(vault, doc, 'x'),
      throwsVault(VaultErrorCode.readOnly),
    );
    expect(storage.bytesOf('Binary.md'), [0x61, 0xFF]);
  });

  test('CRLF and BOM survive an edit', () async {
    storage.setBytes(
      'Win.md',
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('a\r\nb\r\n')]),
    );
    final doc = await repo.open(vault, 'Win.md');
    await repo.save(vault, doc, '${doc.text}c\n');
    expect(storage.bytesOf('Win.md'), [
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('a\r\nb\r\nc\r\n'),
    ]);
  });

  test('history file names do not reveal note paths', () async {
    final doc = await repo.open(vault, 'Inbox/Idea.md');
    await repo.save(vault, doc, 'x');
    final all = tmp.listSync(recursive: true).map((e) => e.path).join('\n');
    expect(all, isNot(contains('Idea')));
    expect(all, isNot(contains('Inbox')));
  });

  test('NoHistory is a no-op', () async {
    const h = NoHistory();
    await h.record('v', 'p', Uint8List(0));
    expect(await h.list('v', 'p'), isEmpty);
  });
}
