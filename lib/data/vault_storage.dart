import 'dart:typed_data';

/// A user-selected vault folder.
class VaultHandle {
  const VaultHandle({required this.id, required this.name});

  /// Opaque identifier (the SAF tree URI on Android). Never shown or logged
  /// beyond what is needed.
  final String id;

  /// Human-readable folder name.
  final String name;

  @override
  bool operator ==(Object other) => other is VaultHandle && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Metadata about a file at the moment it was read or written.
class FileStamp {
  const FileStamp({
    required this.size,
    required this.lastModified,
    required this.sha256,
  });

  final int size;

  /// Milliseconds since epoch as reported by the storage provider (0 if
  /// unknown).
  final int lastModified;

  /// Hex SHA-256 of the file bytes. Used to detect external changes; the
  /// modification time alone is too coarse on some providers.
  final String sha256;
}

class VaultEntry {
  const VaultEntry({
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.lastModified = 0,
  });

  /// Vault-relative path (see VaultPath).
  final String path;
  final bool isDirectory;
  final int size;
  final int lastModified;
}

class FileContent {
  const FileContent({required this.bytes, required this.stamp});
  final Uint8List bytes;
  final FileStamp stamp;
}

class CreatedFile {
  const CreatedFile({required this.path, required this.stamp});
  final String path;
  final FileStamp stamp;
}

enum VaultErrorCode {
  /// The user dismissed the folder picker.
  cancelled,

  /// Android access to the folder is missing or was revoked.
  permissionDenied,
  notFound,
  alreadyExists,

  /// The file changed since it was read; nothing was written.
  conflict,
  tooLarge,
  invalidPath,
  readOnly,
  io,
}

class VaultException implements Exception {
  VaultException(this.code, [this.message]);
  final VaultErrorCode code;
  final String? message;
  @override
  String toString() =>
      'VaultException(${code.name}${message == null ? '' : ': $message'})';
}

/// Storage backend for a vault. Paths are vault-relative and must already be
/// validated with VaultPath; implementations re-validate defensively.
abstract interface class VaultStorage {
  /// Shows the system folder picker. Returns null if cancelled.
  Future<VaultHandle?> pickVault();

  /// Returns the previously selected vault if Android still grants access.
  /// Throws [VaultException] with [VaultErrorCode.permissionDenied] if a vault
  /// was remembered but access is gone.
  Future<VaultHandle?> restoreVault();

  /// Forgets the vault and releases Emerald's persisted permission. Never
  /// touches the files.
  Future<void> forgetVault(VaultHandle vault);

  /// Lists all non-hidden folders and Markdown files below the root.
  Future<List<VaultEntry>> listTree(VaultHandle vault);

  Future<FileContent> readFile(VaultHandle vault, String path);

  /// Overwrites [path] only if its current SHA-256 equals [expectedSha256];
  /// otherwise throws [VaultErrorCode.conflict] without writing.
  Future<FileStamp> writeFile(
    VaultHandle vault,
    String path,
    Uint8List bytes, {
    required String expectedSha256,
  });

  /// Creates a new file. Throws [VaultErrorCode.alreadyExists] if a file with
  /// that name exists; never overwrites.
  /// The returned path is the one actually created (a storage provider may
  /// adjust the requested name).
  Future<CreatedFile> createFile(
    VaultHandle vault,
    String path,
    Uint8List bytes,
  );

  /// Creates a folder (and missing parents). Existing folders are fine.
  Future<void> createDirectory(VaultHandle vault, String path);
}
