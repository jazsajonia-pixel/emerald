import 'package:emerald/features/links/link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> targets(String text) =>
      LinkParser.parse(text).map((l) => l.target).toList();

  test('wiki links with alias, heading, block, embed', () {
    final links = LinkParser.parse(
      'See [[Alpha]], [[Beta|the beta]], [[Gamma#Intro]], '
      '[[Delta#^abc|d]] and ![[Embed]].',
    );
    expect(links.map((l) => l.target), [
      'Alpha',
      'Beta',
      'Gamma',
      'Delta',
      'Embed',
    ]);
    expect(links[1].alias, 'the beta');
    expect(links[2].subpath, 'Intro');
    expect(links[3].subpath, '^abc');
    expect(links[3].alias, 'd');
    expect(links[4].embed, isTrue);
    expect(links.every((l) => l.kind == LinkKind.wiki), isTrue);
  });

  test('same-note heading links are ignored', () {
    expect(targets('[[#Heading]]'), isEmpty);
  });

  test('escaped pipe in tables', () {
    final l = LinkParser.parse(r'| [[Note\|Alias]] |').single;
    expect(l.target, 'Note');
    expect(l.alias, 'Alias');
  });

  test('markdown links: relative, encoded, angle brackets, fragments', () {
    final links = LinkParser.parse(
      '[a](Other.md) [b](../Up/Note%20Two.md#sec) [c](<With Space.md>) '
      '[d](Folder/Plain "title")',
    );
    expect(links.map((l) => l.target), [
      'Other.md',
      '../Up/Note Two.md',
      'With Space.md',
      'Folder/Plain',
    ]);
    expect(links[1].subpath, 'sec');
    expect(links.every((l) => l.kind == LinkKind.markdown), isTrue);
  });

  test('external links, anchors and images are not note links', () {
    expect(
      targets(
        '[w](https://example.com) [m](mailto:a@b.c) [h](#top) '
        '![img](pic.png) [x](obsidian://open?vault=v)',
      ),
      isEmpty,
    );
  });

  test('links inside code are ignored', () {
    const text = '''
Real [[One]].
```
[[NotALink]] [x](nope.md)
```
Inline `[[AlsoNot]]` and ``[y](no.md)`` but [[Two]].
~~~
[[Tilde]]
~~~
''';
    expect(targets(text), ['One', 'Two']);
  });

  test('Unicode targets', () {
    expect(targets('[[Grüße 🌿]] [[日本語|ja]] [é](Café.md)'), [
      'Grüße 🌿',
      '日本語',
      'Café.md',
    ]);
  });

  test('offsets point at the original text', () {
    const text = 'x [[A|b]] y [c](D.md) z';
    for (final l in LinkParser.parse(text)) {
      final s = text.substring(l.start, l.end);
      expect(s.startsWith('[') || s.startsWith('!'), isTrue);
      expect(s.endsWith(']]') || s.endsWith(')'), isTrue);
    }
  });

  test('maskCode preserves length and newlines', () {
    const t = 'a `b` c\n```\ncode\n```\nd';
    final m = LinkParser.maskCode(t);
    expect(m.length, t.length);
    expect('\n'.allMatches(m).length, '\n'.allMatches(t).length);
    expect(m, isNot(contains('code')));
  });
}
