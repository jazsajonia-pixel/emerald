import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Git blob object id: SHA-1 of `"blob <size>\0" + bytes`. Lets Emerald
/// compare a local file with the SHA GitHub reports in a tree without
/// downloading the file.
String gitBlobSha(Uint8List bytes) {
  final header = ascii.encode('blob ${bytes.length}\u0000');
  final b = BytesBuilder(copy: false)
    ..add(header)
    ..add(bytes);
  return sha1.convert(b.takeBytes()).toString();
}
