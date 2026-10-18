import 'dart:convert';
import 'dart:typed_data';

import 'package:sapphire/features/notes/note_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  test('plain UTF-8 round-trips byte-for-byte', () {
    final bytes = b(utf8.encode('# Grüße\n\n日本語 🌿\n'));
    final d = NoteCodec.decode(bytes);
    expect(d.text, '# Grüße\n\n日本語 🌿\n');
    expect(d.readOnly, isFalse);
    expect(NoteCodec.encode(d.text, hasBom: d.hasBom, crlf: d.crlf), bytes);
  });

  test('empty file', () {
    final d = NoteCodec.decode(b([]));
    expect(d.text, '');
    expect(d.readOnly, isFalse);
    expect(NoteCodec.encode(''), isEmpty);
  });

  test('BOM is preserved', () {
    final bytes = b([0xEF, 0xBB, 0xBF, ...utf8.encode('hi')]);
    final d = NoteCodec.decode(bytes);
    expect(d.text, 'hi');
    expect(d.hasBom, isTrue);
    expect(NoteCodec.encode(d.text, hasBom: true), bytes);
  });

  test('consistent CRLF is edited as LF and written back as CRLF', () {
    final bytes = b(utf8.encode('a\r\nb\r\n'));
    final d = NoteCodec.decode(bytes);
    expect(d.text, 'a\nb\n');
    expect(d.crlf, isTrue);
    expect(
      NoteCodec.encode('${d.text}c\n', crlf: true),
      utf8.encode('a\r\nb\r\nc\r\n'),
    );
  });

  test('mixed line endings open read-only', () {
    final d = NoteCodec.decode(b(utf8.encode('a\r\nb\nc')));
    expect(d.readOnly, isTrue);
    expect(d.text, 'a\r\nb\nc');
  });

  test('invalid UTF-8 opens read-only instead of being re-encoded', () {
    final d = NoteCodec.decode(b([0x61, 0xFF, 0x62]));
    expect(d.readOnly, isTrue);
    expect(d.readOnlyReason, contains('UTF-8'));
  });
}
