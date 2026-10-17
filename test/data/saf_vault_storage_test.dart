import 'package:emerald/data/saf_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(SafVaultStorage.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const vault = VaultHandle(id: 'content://tree', name: 'V');
  final calls = <MethodCall>[];

  void handler(Future<Object?>? Function(MethodCall) h) =>
      messenger.setMockMethodCallHandler(channel, (c) {
        calls.add(c);
        return h(c);
      });

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('cancelled picker returns null', () async {
    handler((_) async => throw PlatformException(code: 'CANCELLED'));
    expect(await SafVaultStorage().pickVault(), isNull);
  });

  test('picked vault is returned', () async {
    handler((_) async => {'uri': 'content://tree', 'name': 'Notes'});
    final v = await SafVaultStorage().pickVault();
    expect(v!.name, 'Notes');
  });

  test('platform error codes map to VaultErrorCode', () async {
    for (final entry in {
      'PERMISSION_DENIED': VaultErrorCode.permissionDenied,
      'NOT_FOUND': VaultErrorCode.notFound,
      'CONFLICT': VaultErrorCode.conflict,
      'ALREADY_EXISTS': VaultErrorCode.alreadyExists,
      'TOO_LARGE': VaultErrorCode.tooLarge,
      'READ_ONLY': VaultErrorCode.readOnly,
      'WHATEVER': VaultErrorCode.io,
    }.entries) {
      handler((_) async => throw PlatformException(code: entry.key));
      await expectLater(
        SafVaultStorage().readFile(vault, 'a.md'),
        throwsA(
          isA<VaultException>().having((e) => e.code, 'code', entry.value),
        ),
      );
    }
  });

  test('unsafe paths never reach the platform', () async {
    handler((_) async => null);
    await expectLater(
      SafVaultStorage().readFile(vault, '../x.md'),
      throwsA(isA<VaultException>()),
    );
    expect(calls, isEmpty);
  });

  test('listTree drops entries the Dart validator rejects', () async {
    handler(
      (_) async => [
        {'path': 'ok.md', 'isDir': false, 'size': 3, 'lastModified': 1},
        {'path': '../evil.md', 'isDir': false},
        {'path': '.obsidian', 'isDir': true},
        {'path': 'Folder', 'isDir': true, 'size': 0, 'lastModified': 0},
      ],
    );
    final list = await SafVaultStorage().listTree(vault);
    expect(list.map((e) => e.path), ['ok.md', 'Folder']);
  });

  test('writeFile sends expected hash and bytes', () async {
    handler((c) async => {'size': 2, 'lastModified': 5, 'sha256': 'abc'});
    final s = await SafVaultStorage().writeFile(
      vault,
      'a.md',
      Uint8List.fromList([1, 2]),
      expectedSha256: 'old',
    );
    expect(s.sha256, 'abc');
    expect(calls.single.method, 'writeFile');
    expect((calls.single.arguments as Map)['expectedSha256'], 'old');
  });

  test('createFile returns the real path', () async {
    handler(
      (_) async => {
        'size': 0,
        'lastModified': 1,
        'sha256': 'e',
        'path': 'X.md',
      },
    );
    final c = await SafVaultStorage().createFile(vault, 'X.md', Uint8List(0));
    expect(c.path, 'X.md');
  });
}
