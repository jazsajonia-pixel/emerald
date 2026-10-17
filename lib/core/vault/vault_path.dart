/// Validation and manipulation of vault-relative paths.
///
/// All note paths inside Emerald are relative to the selected vault root and
/// use `/` as separator, e.g. `Projects/Emerald.md`. The empty string is the
/// vault root. Anything that could escape the vault (absolute paths, `..`,
/// backslashes, NUL/control characters) is rejected rather than "fixed".
abstract final class VaultPath {
  static const String root = '';

  /// Folder/file names that Emerald never lists or writes (Obsidian config,
  /// trash, VCS data, and any other dot-entry).
  static bool isIgnoredName(String name) => name.startsWith('.');

  static bool isMarkdown(String path) => path.toLowerCase().endsWith('.md');

  /// Returns the normalized form of [path] or throws [InvalidVaultPath].
  static String normalize(String path) {
    if (path.isEmpty) return root;
    if (path.startsWith('/') || path.contains('\\')) {
      throw InvalidVaultPath(path, 'must be relative and use "/"');
    }
    final parts = path.split('/');
    final out = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final seg = parts[i];
      // Tolerate a single trailing slash for folders.
      if (seg.isEmpty && i == parts.length - 1 && i > 0) continue;
      validateName(seg, original: path);
      out.add(seg);
    }
    return out.join('/');
  }

  /// Validates a single file or folder name.
  static void validateName(String name, {String? original}) {
    final p = original ?? name;
    if (name.isEmpty) throw InvalidVaultPath(p, 'empty path segment');
    if (name == '.' || name == '..') {
      throw InvalidVaultPath(p, 'relative segments are not allowed');
    }
    if (name.contains('/') || name.contains('\\')) {
      throw InvalidVaultPath(p, 'name contains a path separator');
    }
    for (final c in name.codeUnits) {
      if (c < 0x20 || c == 0x7f) {
        throw InvalidVaultPath(p, 'contains control characters');
      }
    }
    if (name.trim() != name) {
      throw InvalidVaultPath(p, 'leading or trailing whitespace');
    }
    if (isIgnoredName(name)) {
      throw InvalidVaultPath(p, 'hidden/internal entries are not accessible');
    }
    const reserved = ['<', '>', ':', '"', '|', '?', '*'];
    for (final r in reserved) {
      if (name.contains(r)) {
        throw InvalidVaultPath(p, 'contains reserved character "$r"');
      }
    }
    if (name.length > 255) throw InvalidVaultPath(p, 'name too long');
  }

  static String join(String dir, String name) {
    final d = normalize(dir);
    validateName(name);
    return d.isEmpty ? name : '$d/$name';
  }

  static String parent(String path) {
    final p = normalize(path);
    final i = p.lastIndexOf('/');
    return i < 0 ? root : p.substring(0, i);
  }

  static String basename(String path) {
    final p = normalize(path);
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  /// Note title: file name without the `.md` extension.
  static String title(String path) {
    final b = basename(path);
    return isMarkdown(b) ? b.substring(0, b.length - 3) : b;
  }

  static List<String> segments(String path) {
    final p = normalize(path);
    return p.isEmpty ? const [] : p.split('/');
  }

  /// Turns a user-entered title into a safe Markdown file name.
  /// Throws [InvalidVaultPath] if nothing usable remains.
  static String fileNameForTitle(String title) {
    var t = title.trim();
    if (isMarkdown(t)) t = t.substring(0, t.length - 3).trim();
    t = t.replaceAll(RegExp(r'[\\/<>:"|?*\x00-\x1f\x7f]'), '-');
    while (t.startsWith('.')) {
      t = t.substring(1);
    }
    t = t.trim();
    if (t.isEmpty) throw InvalidVaultPath(title, 'title is empty');
    final name = '$t.md';
    validateName(name);
    return name;
  }
}

class InvalidVaultPath implements Exception {
  InvalidVaultPath(this.path, this.reason);
  final String path;
  final String reason;
  @override
  String toString() => 'Invalid vault path "$path": $reason';
}
