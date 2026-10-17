import '../search/vault_index.dart';
import 'link_parser.dart';
import 'link_resolver.dart';

/// Rewrites links for the rendered preview so they can be tapped:
/// resolved note links become `emerald-note:<path>`, broken ones
/// `emerald-broken:<target>`. The note file itself is never modified.
abstract final class PreviewLinks {
  static const noteScheme = 'emerald-note:';
  static const brokenScheme = 'emerald-broken:';

  static String prepare(String text, String sourcePath, VaultIndex index) {
    final links = LinkParser.parse(text);
    if (links.isEmpty) return text;
    final resolver = LinkResolver(index.notes.keys);
    final out = StringBuffer();
    var pos = 0;
    for (final l in links) {
      final r = resolver.resolve(sourcePath, l);
      if (r.status == LinkStatus.attachment) continue;
      out.write(text.substring(pos, l.start));
      final label = _escape(
        l.kind == LinkKind.wiki
            ? (l.alias ??
                  (l.subpath == null ? l.target : '${l.target} › ${l.subpath}'))
            : (l.alias ?? l.target),
      );
      final href = r.isNoteLink
          ? '$noteScheme${Uri.encodeComponent(r.targetPath!)}'
          : '$brokenScheme${Uri.encodeComponent(l.target)}';
      out.write('[$label](<$href>)');
      pos = l.end;
    }
    out.write(text.substring(pos));
    return out.toString();
  }

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('[', r'\[').replaceAll(']', r'\]');
}
