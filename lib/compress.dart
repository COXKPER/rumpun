import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pure_zstd/pure_zstd.dart';

/// Cache payloads are JSON, which compresses 5-10x. One place for the codec so
/// `AppStore` never has to know how bytes are stored.
///
/// pure_zstd is plain Dart — no native library, no platform channel, no
/// build-time download, so this also runs in unit tests.
///
/// ponytail: synchronous on the calling isolate. A cached page is a few hundred
/// KB; move to `Isolate.run` if a timeline ever exceeds ~1 MB.
String encodeCache(Object value) {
  final json = utf8.encode(jsonEncode(value));
  try {
    return base64Encode(zstdEncode(Uint8List.fromList(json)));
  } catch (error) {
    // A slower cache beats a crash: store plain JSON and keep going.
    debugPrint('zstd encode failed, caching as JSON: $error');
    return utf8.decode(json);
  }
}

/// Returns null when [raw] is neither zstd nor JSON — a corrupt row must not
/// lose the whole cache read.
Object? decodeCache(String raw) {
  if (raw.startsWith('{') || raw.startsWith('[')) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  try {
    return jsonDecode(utf8.decode(zstdDecode(base64Decode(raw))));
  } catch (_) {
    return null;
  }
}
