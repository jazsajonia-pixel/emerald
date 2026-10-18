import 'dart:convert';

import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/data/vault_storage.dart';
import 'package:sapphire/features/search/index_controller.dart';
import 'package:sapphire/features/vault/vault_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingStorage extends MemoryVaultStorage {
  CountingStorage({super.files, super.remembered});
  int reads = 0;
  @override
  Future<FileContent> readFile(VaultHandle vault, String path) {
    reads++;
    return super.readFile(vault, path);
  }
}

const vault = VaultHandle(id: 'memory://vault', name: 'V');

Future<void> settle(ProviderContainer c) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late CountingStorage storage;
  late ProviderContainer c;

  setUp(() async {
    storage = CountingStorage(
      files: {'A.md': 'links to [[B]]', 'B.md': 'plain', 'Sub/C.md': '[[A]]'},
      remembered: vault,
    );
    c = ProviderContainer.test(
      overrides: [vaultStorageProvider.overrideWithValue(storage)],
    );
    c.listen(indexControllerProvider, (_, _) {});
    await settle(c);
  });

  IndexState idx() => c.read(indexControllerProvider);

  test('indexes all notes once', () {
    expect(idx().index.notes.keys.toSet(), {'A.md', 'B.md', 'Sub/C.md'});
    expect(idx().index.backlinks('B.md'), ['A.md']);
    expect(storage.reads, 3);
  });

  test(
    'rescan re-reads only changed files and picks up external edits',
    () async {
      storage.reads = 0;
      storage.setFile('B.md', 'now links to [[A]]');
      await c.read(vaultControllerProvider.notifier).rescan();
      await settle(c);
      expect(storage.reads, 1);
      expect(idx().index.backlinks('A.md'), ['B.md', 'Sub/C.md']);
    },
  );

  test('deleted notes disappear and their links become broken', () async {
    storage.deleteExternally('B.md');
    await c.read(vaultControllerProvider.notifier).rescan();
    await settle(c);
    expect(idx().index.notes.containsKey('B.md'), isFalse);
    expect(idx().index.brokenLinks('A.md').single.link.target, 'B');
  });

  test('rebuild re-reads everything and never modifies notes', () async {
    final before = {
      for (final p in ['A.md', 'B.md', 'Sub/C.md'])
        p: utf8.decode(storage.bytesOf(p)!),
    };
    storage.reads = 0;
    await c.read(indexControllerProvider.notifier).rebuild();
    await settle(c);
    expect(storage.reads, 3);
    for (final e in before.entries) {
      expect(utf8.decode(storage.bytesOf(e.key)!), e.value);
    }
    expect(
      (await storage.listTree(vault)).where((e) => !e.isDirectory),
      hasLength(3),
    );
  });

  test('updateNote after an Sapphire write avoids re-reading', () async {
    storage.reads = 0;
    final stamp = await storage.writeFile(
      vault,
      'B.md',
      utf8.encode('[[Sub/C]]'),
      expectedSha256: (await storage.readFile(vault, 'B.md')).stamp.sha256,
    );
    storage.reads = 0;
    c
        .read(indexControllerProvider.notifier)
        .updateNote('B.md', '[[Sub/C]]', stamp);
    c.read(vaultControllerProvider.notifier).noteWritten('B.md', stamp);
    await settle(c);
    expect(storage.reads, 0);
    expect(idx().index.backlinks('Sub/C.md'), ['B.md']);
  });

  test('forgetting the vault clears the index', () async {
    await c.read(vaultControllerProvider.notifier).forget();
    await settle(c);
    expect(idx().index.notes, isEmpty);
  });
}
