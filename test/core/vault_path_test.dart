import 'package:emerald/core/vault/vault_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalize', () {
    test('accepts ordinary relative paths', () {
      expect(VaultPath.normalize(''), '');
      expect(VaultPath.normalize('Note.md'), 'Note.md');
      expect(VaultPath.normalize('Projects/Emerald.md'), 'Projects/Emerald.md');
      expect(VaultPath.normalize('Projects/'), 'Projects');
    });

    test('accepts Unicode names', () {
      expect(VaultPath.normalize('Ideen/Grüße 🌿.md'), 'Ideen/Grüße 🌿.md');
      expect(VaultPath.normalize('ノート/日本語.md'), 'ノート/日本語.md');
    });

    for (final bad in [
      '/etc/passwd',
      '../outside.md',
      'a/../../b.md',
      'a/./b.md',
      'a//b.md',
      r'a\b.md',
      '.obsidian/workspace.json',
      'notes/.hidden.md',
      'bad\u0000name.md',
      'tab\tname.md',
      ' leading.md',
      'q?.md',
      'c:drive.md',
    ]) {
      test('rejects "$bad"', () {
        expect(
          () => VaultPath.normalize(bad),
          throwsA(isA<InvalidVaultPath>()),
        );
      });
    }

    test('rejects overly long names', () {
      expect(
        () => VaultPath.normalize('${'a' * 300}.md'),
        throwsA(isA<InvalidVaultPath>()),
      );
    });
  });

  test('join, parent, basename, title, segments', () {
    expect(VaultPath.join('', 'A.md'), 'A.md');
    expect(VaultPath.join('x/y', 'A.md'), 'x/y/A.md');
    expect(
      () => VaultPath.join('x', '../A.md'),
      throwsA(isA<InvalidVaultPath>()),
    );
    expect(VaultPath.parent('x/y/A.md'), 'x/y');
    expect(VaultPath.parent('A.md'), '');
    expect(VaultPath.basename('x/y/A.md'), 'A.md');
    expect(VaultPath.title('x/Daily Note.MD'), 'Daily Note');
    expect(VaultPath.segments('x/y/A.md'), ['x', 'y', 'A.md']);
    expect(VaultPath.segments(''), isEmpty);
  });

  test('fileNameForTitle sanitises user titles', () {
    expect(VaultPath.fileNameForTitle('Meeting notes'), 'Meeting notes.md');
    expect(VaultPath.fileNameForTitle('Plan.md'), 'Plan.md');
    expect(VaultPath.fileNameForTitle('a/b: c?'), 'a-b- c-.md');
    expect(VaultPath.fileNameForTitle('..secret'), 'secret.md');
    expect(VaultPath.fileNameForTitle('Café ☕'), 'Café ☕.md');
    expect(
      () => VaultPath.fileNameForTitle('   '),
      throwsA(isA<InvalidVaultPath>()),
    );
    expect(
      () => VaultPath.fileNameForTitle('...'),
      throwsA(isA<InvalidVaultPath>()),
    );
  });

  test('ignored names and markdown detection', () {
    expect(VaultPath.isIgnoredName('.obsidian'), isTrue);
    expect(VaultPath.isIgnoredName('.trash'), isTrue);
    expect(VaultPath.isIgnoredName('Notes'), isFalse);
    expect(VaultPath.isMarkdown('a.md'), isTrue);
    expect(VaultPath.isMarkdown('a.MD'), isTrue);
    expect(VaultPath.isMarkdown('a.txt'), isFalse);
  });
}
