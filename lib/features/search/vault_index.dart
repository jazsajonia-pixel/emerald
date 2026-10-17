import '../../core/vault/vault_path.dart';
import '../links/link_parser.dart';
import '../links/link_resolver.dart';

/// Derived, in-memory index of a vault. It is always rebuilt from the
/// Markdown files and never written back to them.
class IndexedNote {
  IndexedNote({
    required this.path,
    required this.text,
    required this.lastModified,
    required this.size,
  }) : title = VaultPath.title(path),
       lowerText = text.toLowerCase(),
       links = LinkParser.parse(text);

  final String path;
  final String title;
  final String text;
  final String lowerText;
  final int lastModified;
  final int size;
  final List<ParsedLink> links;
}

class SearchHit {
  const SearchHit({required this.path, required this.score, this.snippet});
  final String path;
  final int score;
  final String? snippet;
}

class VaultIndex {
  VaultIndex(Map<String, IndexedNote> notes, {this.unreadable = const []})
    : notes = Map.unmodifiable(notes) {
    final resolver = LinkResolver(this.notes.keys);
    for (final n in this.notes.values) {
      final resolved = [for (final l in n.links) resolver.resolve(n.path, l)];
      _outgoing[n.path] = resolved;
      for (final r in resolved) {
        final t = r.targetPath;
        if (r.isNoteLink && t != null && t != n.path) {
          (_backlinks[t] ??= <String>{}).add(n.path);
        }
      }
    }
  }

  static final empty = VaultIndex(const {});

  final Map<String, IndexedNote> notes;

  /// Notes that could not be read (too large, permission, I/O).
  final List<String> unreadable;
  final Map<String, List<ResolvedLink>> _outgoing = {};
  final Map<String, Set<String>> _backlinks = {};

  List<ResolvedLink> outgoing(String path) => _outgoing[path] ?? const [];

  /// Distinct notes this note links to (excluding itself).
  Set<String> linkedTargets(String path) => {
    for (final r in outgoing(path))
      if (r.isNoteLink && r.targetPath != path) r.targetPath!,
  };

  List<String> backlinks(String path) =>
      (_backlinks[path]?.toList() ?? <String>[])..sort();

  List<ResolvedLink> brokenLinks(String path) => [
    for (final r in outgoing(path))
      if (r.status == LinkStatus.broken || r.status == LinkStatus.outsideVault)
        r,
  ];

  /// Notes with neither outgoing note links nor backlinks.
  List<String> get orphans =>
      notes.keys
          .where((p) => linkedTargets(p).isEmpty && backlinks(p).isEmpty)
          .toList()
        ..sort();

  /// Unique explicit edges (source → target) between distinct notes.
  Iterable<(String, String)> get edges sync* {
    for (final p in notes.keys) {
      for (final t in linkedTargets(p)) {
        yield (p, t);
      }
    }
  }

  /// Case-insensitive search over titles and contents. All whitespace-
  /// separated terms must match (in the title or the text).
  List<SearchHit> search(String query, {int limit = 100}) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return const [];
    final hits = <SearchHit>[];
    for (final n in notes.values) {
      final lowerTitle = n.title.toLowerCase();
      final lowerPath = n.path.toLowerCase();
      var score = 0;
      var ok = true;
      int? firstPos;
      for (final t in terms) {
        final inTitle = lowerTitle.contains(t);
        final pos = n.lowerText.indexOf(t);
        if (!inTitle && pos < 0 && !lowerPath.contains(t)) {
          ok = false;
          break;
        }
        if (lowerTitle == t) score += 100;
        if (inTitle) score += 40;
        if (lowerTitle.startsWith(t)) score += 10;
        if (pos >= 0) {
          score += 5 + _count(n.lowerText, t).clamp(0, 20);
          firstPos ??= pos;
        } else if (!inTitle) {
          score += 2; // matched folder name only
        }
      }
      if (!ok) continue;
      hits.add(
        SearchHit(
          path: n.path,
          score: score,
          snippet: firstPos == null ? null : _snippet(n.text, firstPos),
        ),
      );
    }
    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.path.compareTo(b.path);
    });
    return hits.take(limit).toList();
  }

  static int _count(String haystack, String needle) {
    var n = 0;
    var i = haystack.indexOf(needle);
    while (i >= 0) {
      n++;
      i = haystack.indexOf(needle, i + needle.length);
    }
    return n;
  }

  static String _snippet(String text, int pos) {
    final start = (pos - 40).clamp(0, text.length);
    final end = (pos + 80).clamp(0, text.length);
    final s = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${start > 0 ? '…' : ''}$s${end < text.length ? '…' : ''}';
  }
}
