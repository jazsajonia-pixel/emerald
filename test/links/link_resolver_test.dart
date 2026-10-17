import 'package:emerald/features/links/link_parser.dart';
import 'package:emerald/features/links/link_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final resolver = LinkResolver([
    'Home.md',
    'Projects/Emerald.md',
    'Projects/Plan.md',
    'Archive/Plan.md',
    'Deep/Nested/Leaf.md',
    'Ideen/Grüße.md',
    'Mixed Case.md',
  ]);

  ResolvedLink r(String source, String text) =>
      resolver.resolve(source, LinkParser.parse(text).single);

  test('wiki link by title', () {
    final x = r('Home.md', '[[Emerald]]');
    expect(x.status, LinkStatus.resolved);
    expect(x.targetPath, 'Projects/Emerald.md');
  });

  test('wiki link is case-insensitive', () {
    expect(r('Home.md', '[[mixed case]]').targetPath, 'Mixed Case.md');
  });

  test('duplicate names: same folder preferred, marked ambiguous', () {
    final fromProjects = r('Projects/Emerald.md', '[[Plan]]');
    expect(fromProjects.status, LinkStatus.ambiguous);
    expect(fromProjects.targetPath, 'Projects/Plan.md');
    expect(fromProjects.candidates, hasLength(2));
    expect(r('Archive/Plan.md', '[[Plan]]').targetPath, 'Archive/Plan.md');
  });

  test('wiki link with folder disambiguates', () {
    final x = r('Home.md', '[[Archive/Plan]]');
    expect(x.status, LinkStatus.resolved);
    expect(x.targetPath, 'Archive/Plan.md');
    expect(r('Home.md', '[[Nested/Leaf]]').targetPath, 'Deep/Nested/Leaf.md');
  });

  test('wiki link with .md extension', () {
    expect(r('Home.md', '[[Emerald.md]]').targetPath, 'Projects/Emerald.md');
  });

  test('broken and missing/renamed notes', () {
    expect(r('Home.md', '[[Renamed Away]]').status, LinkStatus.broken);
    expect(r('Home.md', '[x](Missing.md)').status, LinkStatus.broken);
  });

  test('markdown relative links', () {
    expect(
      r('Projects/Emerald.md', '[p](Plan.md)').targetPath,
      'Projects/Plan.md',
    );
    expect(r('Projects/Emerald.md', '[h](../Home.md)').targetPath, 'Home.md');
    expect(
      r('Projects/Emerald.md', '[a](../Archive/Plan.md)').targetPath,
      'Archive/Plan.md',
    );
    expect(
      r('Home.md', '[e](Projects/Emerald)').targetPath,
      'Projects/Emerald.md',
    );
    expect(r('Deep/Nested/Leaf.md', '[r](/Home.md)').targetPath, 'Home.md');
    expect(
      r('Home.md', '[g](Ideen/Gr%C3%BC%C3%9Fe.md)').targetPath,
      'Ideen/Grüße.md',
    );
  });

  test('links cannot escape the vault', () {
    expect(r('Home.md', '[x](../secret.md)').status, LinkStatus.outsideVault);
    expect(
      r('Projects/Emerald.md', '[x](../../../etc/passwd.md)').status,
      LinkStatus.outsideVault,
    );
    expect(r('Home.md', '[[../secret]]').status, LinkStatus.outsideVault);
  });

  test('attachments are not note links', () {
    expect(r('Home.md', '[pdf](doc.pdf)').status, LinkStatus.attachment);
    expect(r('Home.md', '![[diagram.png]]').status, LinkStatus.attachment);
  });
}
