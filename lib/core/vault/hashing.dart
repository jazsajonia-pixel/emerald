import 'package:crypto/crypto.dart';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
