import 'package:flutter/services.dart';

import '../core/vault/vault_path.dart';
import 'vault_storage.dart';

/// [VaultStorage] backed by Android's Storage Access Framework through the
/// Kotlin channel in `android/app/src/main/kotlin/.../VaultChannel.kt`.
class SafVaultStorage implements VaultStorage {
  SafVaultStorage([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'io.github.jazsajonia.sapphire/vault';
  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw VaultException(_code(e.code), e.message);
    } on MissingPluginException {
      throw VaultException(
        VaultErrorCode.io,
        'Vault access is only available on Android.',
      );
    }
  }

  static VaultErrorCode _code(String code) => switch (code) {
    'CANCELLED' => VaultErrorCode.cancelled,
    'PERMISSION_DENIED' => VaultErrorCode.permissionDenied,
    'NOT_FOUND' => VaultErrorCode.notFound,
    'ALREADY_EXISTS' => VaultErrorCode.alreadyExists,
    'CONFLICT' => VaultErrorCode.conflict,
    'TOO_LARGE' => VaultErrorCode.tooLarge,
    'INVALID_PATH' => VaultErrorCode.invalidPath,
    'READ_ONLY' => VaultErrorCode.readOnly,
    _ => VaultErrorCode.io,
  };

  String _valid(String path) {
    try {
      return VaultPath.normalize(path);
    } on InvalidVaultPath catch (e) {
      throw VaultException(VaultErrorCode.invalidPath, e.reason);
    }
  }

  static VaultHandle? _handle(Map<Object?, Object?>? m) => m == null
      ? null
      : VaultHandle(id: m['uri']! as String, name: m['name']! as String);

  static FileStamp _stamp(Map<Object?, Object?> m) => FileStamp(
    size: (m['size'] as num).toInt(),
    lastModified: (m['lastModified'] as num).toInt(),
    sha256: m['sha256']! as String,
  );

  @override
  Future<VaultHandle?> pickVault() async {
    try {
      return _handle(await _call<Map<Object?, Object?>>('pickVault'));
    } on VaultException catch (e) {
      if (e.code == VaultErrorCode.cancelled) return null;
      rethrow;
    }
  }

  @override
  Future<VaultHandle?> restoreVault() async =>
      _handle(await _call<Map<Object?, Object?>>('restoreVault'));

  @override
  Future<void> forgetVault(VaultHandle vault) =>
      _call<void>('forgetVault', {'uri': vault.id});

  @override
  Future<List<VaultEntry>> listTree(VaultHandle vault) async {
    final list = await _call<List<Object?>>('listTree', {'uri': vault.id});
    final out = <VaultEntry>[];
    for (final raw in list ?? const []) {
      final m = raw! as Map<Object?, Object?>;
      final path = m['path']! as String;
      // Defence in depth: drop anything the Dart side considers unsafe.
      try {
        VaultPath.normalize(path);
      } on InvalidVaultPath {
        continue;
      }
      out.add(
        VaultEntry(
          path: path,
          isDirectory: m['isDir']! as bool,
          size: (m['size'] as num?)?.toInt() ?? 0,
          lastModified: (m['lastModified'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }

  @override
  Future<FileContent> readFile(VaultHandle vault, String path) async {
    final m = await _call<Map<Object?, Object?>>('readFile', {
      'uri': vault.id,
      'path': _valid(path),
    });
    return FileContent(bytes: m!['bytes']! as Uint8List, stamp: _stamp(m));
  }

  @override
  Future<FileStamp> writeFile(
    VaultHandle vault,
    String path,
    Uint8List bytes, {
    required String expectedSha256,
  }) async {
    final m = await _call<Map<Object?, Object?>>('writeFile', {
      'uri': vault.id,
      'path': _valid(path),
      'bytes': bytes,
      'expectedSha256': expectedSha256,
    });
    return _stamp(m!);
  }

  @override
  Future<CreatedFile> createFile(
    VaultHandle vault,
    String path,
    Uint8List bytes,
  ) async {
    final m = await _call<Map<Object?, Object?>>('createFile', {
      'uri': vault.id,
      'path': _valid(path),
      'bytes': bytes,
    });
    return CreatedFile(path: m!['path']! as String, stamp: _stamp(m));
  }

  @override
  Future<void> createDirectory(VaultHandle vault, String path) =>
      _call<void>('createDirectory', {'uri': vault.id, 'path': _valid(path)});

  @override
  Future<void> deleteFile(
    VaultHandle vault,
    String path, {
    required String expectedSha256,
  }) => _call<void>('deleteFile', {
    'uri': vault.id,
    'path': _valid(path),
    'expectedSha256': expectedSha256,
  });

  /// App-private directory (not inside the vault) for history/cache data.
  Future<String> appFilesDir() async => (await _call<String>('appFilesDir'))!;
}
