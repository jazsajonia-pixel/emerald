/// Extracts note links from Markdown text.
///
/// Supported:
/// - Standard links `[text](Other%20Note.md)`, `[text](<Other Note.md>)`,
///   `[text](../Folder/Note.md#heading)`.
/// - Obsidian wiki links `[[Note]]`, `[[Folder/Note]]`, `[[Note|alias]]`,
///   `[[Note#Heading]]`, `[[Note#^block|alias]]`, and embeds `![[Note]]`.
///
/// Ignored: images `![..](..)`, external URLs (`https:`, `mailto:` …), pure
/// anchors (`#x`), and anything inside fenced code blocks or inline code.
enum LinkKind { markdown, wiki }

class ParsedLink {
  const ParsedLink({
    required this.kind,
    required this.target,
    this.subpath,
    this.alias,
    this.embed = false,
    required this.start,
    required this.end,
  });

  final LinkKind kind;

  /// Wiki: the link text before `#`/`|` (e.g. `Folder/Note`).
  /// Markdown: the percent-decoded path without fragment (e.g. `../a b.md`).
  final String target;
  final String? subpath;
  final String? alias;
  final bool embed;

  /// Offsets of the whole link in the source text.
  final int start;
  final int end;
}

abstract final class LinkParser {
  static final _wiki = RegExp(r'(!?)\[\[([^\[\]\n]+?)\]\]');
  static final _md = RegExp(
    r'(!?)\[((?:[^\[\]\n]|\[[^\[\]\n]*\])*)\]\(\s*(<[^>\n]*>|[^)\s]+)(?:\s+"[^"\n]*")?\s*\)',
  );
  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

  /// Returns [text] with code (fenced blocks and inline spans) replaced by
  /// spaces, preserving offsets and line breaks.
  static String maskCode(String text) {
    final out = StringBuffer();
    String? fence;
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      final isFenceLine =
          (fence == null &&
              (trimmed.startsWith('```') || trimmed.startsWith('~~~'))) ||
          (fence != null && trimmed.startsWith(fence));
      if (isFenceLine) {
        fence = fence == null ? trimmed.substring(0, 3) : null;
        out.write(' ' * line.length);
      } else if (fence != null) {
        out.write(' ' * line.length);
      } else {
        out.write(_maskInline(line));
      }
      if (i < lines.length - 1) out.write('\n');
    }
    return out.toString();
  }

  static String _maskInline(String line) {
    if (!line.contains('`')) return line;
    final chars = line.split('');
    var i = 0;
    while (i < chars.length) {
      if (chars[i] != '`') {
        i++;
        continue;
      }
      var run = 0;
      while (i + run < chars.length && chars[i + run] == '`') {
        run++;
      }
      final ticks = '`' * run;
      final close = line.indexOf(ticks, i + run);
      if (close < 0) {
        i += run;
        continue;
      }
      for (var k = i; k < close + run; k++) {
        chars[k] = ' ';
      }
      i = close + run;
    }
    return chars.join();
  }

  static List<ParsedLink> parse(String text) {
    final masked = maskCode(text);
    final links = <ParsedLink>[];
    for (final m in _wiki.allMatches(masked)) {
      final inner = m.group(2)!.replaceAll(r'\|', '|');
      final pipe = inner.indexOf('|');
      final dest = (pipe < 0 ? inner : inner.substring(0, pipe)).trim();
      final alias = pipe < 0 ? null : inner.substring(pipe + 1).trim();
      final hash = dest.indexOf('#');
      final target = (hash < 0 ? dest : dest.substring(0, hash)).trim();
      if (target.isEmpty) continue; // same-note heading link
      links.add(
        ParsedLink(
          kind: LinkKind.wiki,
          target: target,
          subpath: hash < 0 ? null : dest.substring(hash + 1),
          alias: alias?.isEmpty == true ? null : alias,
          embed: m.group(1) == '!',
          start: m.start,
          end: m.end,
        ),
      );
    }
    for (final m in _md.allMatches(masked)) {
      if (m.group(1) == '!') continue; // image
      if (_insideAny(m.start, links)) continue;
      var dest = m.group(3)!;
      if (dest.startsWith('<') && dest.endsWith('>')) {
        dest = dest.substring(1, dest.length - 1);
      }
      if (dest.isEmpty || dest.startsWith('#') || _scheme.hasMatch(dest)) {
        continue;
      }
      String? subpath;
      final hash = dest.indexOf('#');
      if (hash >= 0) {
        subpath = dest.substring(hash + 1);
        dest = dest.substring(0, hash);
      }
      final q = dest.indexOf('?');
      if (q >= 0) dest = dest.substring(0, q);
      try {
        dest = Uri.decodeComponent(dest);
      } on ArgumentError {
        // Keep the raw text if it is not valid percent-encoding.
      }
      if (dest.isEmpty) continue;
      links.add(
        ParsedLink(
          kind: LinkKind.markdown,
          target: dest,
          subpath: subpath,
          alias: m.group(2),
          start: m.start,
          end: m.end,
        ),
      );
    }
    links.sort((a, b) => a.start.compareTo(b.start));
    return links;
  }

  static bool _insideAny(int pos, List<ParsedLink> links) =>
      links.any((l) => pos >= l.start && pos < l.end);
}
