import 'dart:convert';
import 'dart:typed_data';

/// Converts between file bytes and editor text without silently changing
/// anything the user did not edit.
///
/// - UTF-8 with or without BOM is supported; the BOM is preserved.
/// - Files using CRLF consistently are edited as LF and written back as CRLF.
/// - Invalid UTF-8 or mixed/lone CR line endings open read-only, because
///   saving would rewrite bytes the user never touched.
class DecodedNote {
  const DecodedNote({
    required this.text,
    required this.hasBom,
    required this.crlf,
    this.readOnlyReason,
  });

  final String text;
  final bool hasBom;
  final bool crlf;
  final String? readOnlyReason;

  bool get readOnly => readOnlyReason != null;
}

abstract final class NoteCodec {
  static const _bom = [0xEF, 0xBB, 0xBF];

  static DecodedNote decode(Uint8List bytes) {
    var body = bytes;
    var hasBom = false;
    if (bytes.length >= 3 &&
        bytes[0] == _bom[0] &&
        bytes[1] == _bom[1] &&
        bytes[2] == _bom[2]) {
      hasBom = true;
      body = Uint8List.sublistView(bytes, 3);
    }
    String text;
    try {
      text = utf8.decode(body);
    } on FormatException {
      return DecodedNote(
        text: utf8.decode(body, allowMalformed: true),
        hasBom: hasBom,
        crlf: false,
        readOnlyReason:
            'This file is not valid UTF-8 text, so it is shown read-only to '
            'avoid damaging it.',
      );
    }
    final crCount = '\r'.allMatches(text).length;
    if (crCount == 0) {
      return DecodedNote(text: text, hasBom: hasBom, crlf: false);
    }
    final crlfCount = '\r\n'.allMatches(text).length;
    final lfCount = '\n'.allMatches(text).length;
    if (crCount == crlfCount && crlfCount == lfCount) {
      return DecodedNote(
        text: text.replaceAll('\r\n', '\n'),
        hasBom: hasBom,
        crlf: true,
      );
    }
    return DecodedNote(
      text: text,
      hasBom: hasBom,
      crlf: false,
      readOnlyReason:
          'This file mixes line-ending styles, so it is shown read-only to '
          'avoid rewriting lines you did not edit.',
    );
  }

  static Uint8List encode(
    String text, {
    bool hasBom = false,
    bool crlf = false,
  }) {
    final normalized = crlf
        ? text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
        : text;
    final body = utf8.encode(normalized);
    if (!hasBom) return Uint8List.fromList(body);
    return Uint8List.fromList([..._bom, ...body]);
  }
}
