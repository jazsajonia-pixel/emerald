import '../../core/vault/vault_path.dart';
import 'link_parser.dart';

enum LinkStatus {
  resolved,

  /// Several notes match a wiki link; the best candidate was chosen.
  ambiguous,

  /// No note matches.
  broken,

  /// The link points outside the vault (e.g. `../../x.md` from the root).
  outsideVault,

  /// Points to a non-Markdown attachment (image, PDF …); not a note link.
  attachment,
}

class ResolvedLink {
  const ResolvedLink({
    required this.link,
    required this.status,
    this.targetPath,
    this.candidates = const [],
  });

  final ParsedLink link;
  final LinkStatus status;

  /// Vault-relative path of the target note, when resolved/ambiguous.
  final String? targetPath;
  final List<String> candidates;

  bool get isNoteLink =>
      status == LinkStatus.resolved || status == LinkStatus.ambiguous;
}

/// Resolves links against the set of notes in the vault. Resolution never
/// touches storage — it only matches against known paths — so it cannot be
/// used to reach files outside the vault.
class LinkResolver {
  LinkResolver(Iterable<String> notePaths) {
    for (final p in notePaths) {
      _paths.add(p);
      _lowerPaths.putIfAbsent(p.toLowerCase(), () => []).add(p);
      _byTitle.putIfAbsent(VaultPath.title(p).toLowerCase(), () => []).add(p);
    }
  }

  final Set<String> _paths = {};
  final Map<String, List<String>> _lowerPaths = {};
  final Map<String, List<String>> _byTitle = {};

  static final _ext = RegExp(r'\.([A-Za-z0-9]{1,8})$');

  ResolvedLink resolve(String sourcePath, ParsedLink link) =>
      link.kind == LinkKind.wiki
      ? _wiki(sourcePath, link)
      : _markdown(sourcePath, link);

  ResolvedLink _markdown(String source, ParsedLink link) {
    var t = link.target.trim();
    final segs = <String>[];
    if (t.startsWith('/')) {
      t = t.substring(1);
    } else {
      segs.addAll(VaultPath.segments(VaultPath.parent(source)));
    }
    for (final s in t.split('/')) {
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (segs.isEmpty) {
          return ResolvedLink(link: link, status: LinkStatus.outsideVault);
        }
        segs.removeLast();
        continue;
      }
      segs.add(s);
    }
    if (segs.isEmpty) {
      return ResolvedLink(link: link, status: LinkStatus.broken);
    }
    var path = segs.join('/');
    final ext = _ext.firstMatch(segs.last)?.group(1)?.toLowerCase();
    if (ext != null && ext != 'md') {
      return ResolvedLink(link: link, status: LinkStatus.attachment);
    }
    if (ext == null) path = '$path.md';
    if (_paths.contains(path)) {
      return ResolvedLink(
        link: link,
        status: LinkStatus.resolved,
        targetPath: path,
      );
    }
    final ci = _lowerPaths[path.toLowerCase()];
    if (ci != null && ci.isNotEmpty) {
      return ResolvedLink(
        link: link,
        status: ci.length == 1 ? LinkStatus.resolved : LinkStatus.ambiguous,
        targetPath: ci.first,
        candidates: ci,
      );
    }
    return ResolvedLink(link: link, status: LinkStatus.broken);
  }

  ResolvedLink _wiki(String source, ParsedLink link) {
    var t = link.target.trim();
    if (t.startsWith('/')) t = t.substring(1);
    final ext = _ext.firstMatch(t)?.group(1)?.toLowerCase();
    if (ext != null && ext != 'md' && !_byTitle.containsKey(t.toLowerCase())) {
      return ResolvedLink(link: link, status: LinkStatus.attachment);
    }
    if (ext == 'md') t = t.substring(0, t.length - 3);
    if (t.split('/').contains('..')) {
      return ResolvedLink(link: link, status: LinkStatus.outsideVault);
    }
    final List<String> candidates;
    if (t.contains('/')) {
      final suffix = '${t.toLowerCase()}.md';
      candidates = [
        for (final p in _paths)
          if (p.toLowerCase() == suffix || p.toLowerCase().endsWith('/$suffix'))
            p,
      ];
    } else {
      candidates = List.of(_byTitle[t.toLowerCase()] ?? const <String>[]);
    }
    if (candidates.isEmpty) {
      return ResolvedLink(link: link, status: LinkStatus.broken);
    }
    final sourceDir = VaultPath.parent(source);
    final wanted = t.split('/').last;
    candidates.sort((a, b) {
      int rank(String p) {
        var r = 0;
        if (VaultPath.title(p) != wanted) r += 4; // inexact case
        if (VaultPath.parent(p) != sourceDir) r += 2; // not same folder
        return r;
      }

      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      final d = '/'.allMatches(a).length.compareTo('/'.allMatches(b).length);
      return d != 0 ? d : a.compareTo(b);
    });
    return ResolvedLink(
      link: link,
      status: candidates.length == 1
          ? LinkStatus.resolved
          : LinkStatus.ambiguous,
      targetPath: candidates.first,
      candidates: candidates,
    );
  }
}
