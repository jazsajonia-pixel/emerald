import 'dart:convert';
import 'dart:typed_data';

import '../core/vault/hashing.dart';
import '../core/vault/vault_path.dart';
import 'vault_storage.dart';

/// In-memory [VaultStorage] used by tests and for exercising the UI without a
/// real Android folder. Behaves like the SAF backend with respect to
/// validation, conflicts and errors.
class MemoryVaultStorage implements VaultStorage {
  MemoryVaultStorage({
    Map<String, String> files = const {},
    this.vaultToPick = const VaultHandle(id: 'memory://vault', name: 'Vault'),
    this.remembered,
  }) {
    files.forEach((p, c) => setFile(p, c));
  }

  final Map<String, Uint8List> _files = {};
  final Map<String, int> _mtime = {};
  final Set<String> _dirs = {};
  VaultHandle? vaultToPick;
  VaultHandle? remembered;
  bool accessRevoked = false;
  int _clock = 1000;

  /// Simulates an external editor writing a file.
  void setFile(String path, String content) =>
      setBytes(path, Uint8List.fromList(utf8.encode(content)));

  void setBytes(String path, Uint8List bytes) {
    final p = VaultPath.normalize(path);
    _files[p] = bytes;
    _mtime[p] = ++_clock;
    var d = VaultPath.parent(p);
    while (d.isNotEmpty) {
      _dirs.add(d);
      d = VaultPath.parent(d);
    }
  }

  void deleteExternally(String path) => _files.remove(path);

  Uint8List? bytesOf(String path) => _files[path];

  void _check(VaultHandle vault) {
    if (accessRevoked) throw VaultException(VaultErrorCode.permissionDenied);
  }

  String _valid(String path) {
    try {
      return VaultPath.normalize(path);
    } on InvalidVaultPath catch (e) {
      throw VaultException(VaultErrorCode.invalidPath, e.reason);
    }
  }

  FileStamp _stamp(String p) => FileStamp(
    size: _files[p]!.length,
    lastModified: _mtime[p]!,
    sha256: sha256Hex(_files[p]!),
  );

  @override
  Future<VaultHandle?> pickVault() async {
    remembered = vaultToPick;
    accessRevoked = false;
    return vaultToPick;
  }

  @override
  Future<VaultHandle?> restoreVault() async {
    if (remembered != null && accessRevoked) {
      throw VaultException(VaultErrorCode.permissionDenied);
    }
    return remembered;
  }

  @override
  Future<void> forgetVault(VaultHandle vault) async => remembered = null;

  @override
  Future<List<VaultEntry>> listTree(VaultHandle vault) async {
    _check(vault);
    return [
      for (final d in _dirs) VaultEntry(path: d, isDirectory: true),
      for (final e in _files.entries)
        if (VaultPath.isMarkdown(e.key))
          VaultEntry(
            path: e.key,
            isDirectory: false,
            size: e.value.length,
            lastModified: _mtime[e.key]!,
          ),
    ];
  }

  @override
  Future<FileContent> readFile(VaultHandle vault, String path) async {
    _check(vault);
    final p = _valid(path);
    final b = _files[p];
    if (b == null) throw VaultException(VaultErrorCode.notFound, p);
    return FileContent(bytes: Uint8List.fromList(b), stamp: _stamp(p));
  }

  @override
  Future<FileStamp> writeFile(
    VaultHandle vault,
    String path,
    Uint8List bytes, {
    required String expectedSha256,
  }) async {
    _check(vault);
    final p = _valid(path);
    final cur = _files[p];
    if (cur == null) throw VaultException(VaultErrorCode.notFound, p);
    if (sha256Hex(cur) != expectedSha256) {
      throw VaultException(VaultErrorCode.conflict, p);
    }
    _files[p] = Uint8List.fromList(bytes);
    _mtime[p] = ++_clock;
    return _stamp(p);
  }

  @override
  Future<CreatedFile> createFile(
    VaultHandle vault,
    String path,
    Uint8List bytes,
  ) async {
    _check(vault);
    final p = _valid(path);
    if (_files.containsKey(p) || _dirs.contains(p)) {
      throw VaultException(VaultErrorCode.alreadyExists, p);
    }
    final parent = VaultPath.parent(p);
    if (parent.isNotEmpty && !_dirs.contains(parent)) {
      throw VaultException(VaultErrorCode.notFound, parent);
    }
    setBytes(p, Uint8List.fromList(bytes));
    return CreatedFile(path: p, stamp: _stamp(p));
  }

  @override
  Future<void> createDirectory(VaultHandle vault, String path) async {
    _check(vault);
    var p = _valid(path);
    while (p.isNotEmpty) {
      if (_files.containsKey(p)) {
        throw VaultException(VaultErrorCode.alreadyExists, p);
      }
      _dirs.add(p);
      p = VaultPath.parent(p);
    }
  }
}
