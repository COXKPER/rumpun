import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Codec, ImmutableBuffer, TargetImageSize;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Network images with a shared on-disk cache, so repeated launches and
/// scrolls stop hammering the origin server. In-memory cache still applies
/// on top (Flutter decodes once per key).
///
/// ponytail: whole-file cache with no eviction or freshness checks; files are
/// small and the dir grows slowly. Upgrade: LRU trim + cache-control headers
/// when the directory exceeds ~200 MB.
class CachedNetworkImage extends ImageProvider<CachedNetworkImage> {
  const CachedNetworkImage(this.url, {this.maxWidthPx, this.maxHeightPx});

  final String url;
  final int? maxWidthPx;
  final int? maxHeightPx;

  static Directory? _cacheDir;

  /// One pooled client: a fresh HttpClient per image meant a TLS handshake
  /// and a new socket for every tile while scrolling.
  static final HttpClient _client = HttpClient()
    ..maxConnectionsPerHost = 6
    ..idleTimeout = const Duration(seconds: 30);

  static Future<Directory> cacheDir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/media-cache');
    await dir.create(recursive: true);
    return _cacheDir = dir;
  }

  /// Removes every cached media file (Settings → Clear cache).
  static Future<void> wipe() async {
    final dir = await cacheDir();
    if (dir.existsSync()) {
      await for (final entry in dir.list()) {
        try {
          await entry.delete();
        } on FileSystemException {
          // A file vanishing mid-wipe is fine.
        }
      }
    }
  }

  /// Downloads [url] into the shared media cache and returns the file, or
  /// null when the caller should stream it instead (too large, or a failure).
  /// Keeps whole video/audio files out of memory: media_kit plays from disk.
  static Future<File?> cachedFile(String url, {int maxBytes = 25 << 20}) async {
    final dir = await cacheDir();
    final file = File('${dir.path}/media_'
        '${Uri.encodeComponent(url).hashCode.abs()}');
    if (file.existsSync()) return file;
    try {
      final request = await _client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      if (response.contentLength > maxBytes) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response) {
        total += chunk.length;
        if (total > maxBytes) return null;
        builder.add(chunk);
      }
      await file.writeAsBytes(builder.takeBytes(), flush: false);
      return file;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CachedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedNetworkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
    );
  }

  Future<Codec> _load(CachedNetworkImage key, ImageDecoderCallback decode) async {
    final dir = await cacheDir();
    final file = File('${dir.path}/${Uri.encodeComponent(key.url).hashCode.abs()}'
        '_${key.maxWidthPx ?? 0}_${key.maxHeightPx ?? 0}');
    Uint8List bytes;
    if (file.existsSync()) {
      bytes = await file.readAsBytes();
    } else {
      final response = await _client.getUrl(Uri.parse(key.url))
          .then((request) => request.close());
      if (response.statusCode != 200) {
        throw NetworkImageLoadException(
            statusCode: response.statusCode, uri: Uri.parse(key.url));
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
      await file.writeAsBytes(bytes, flush: false);
    }
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer, getTargetSize: (intrinsicWidth, intrinsicHeight) {
      if (key.maxWidthPx == null && key.maxHeightPx == null) {
        return TargetImageSize(width: intrinsicWidth, height: intrinsicHeight);
      }
      var width = intrinsicWidth;
      var height = intrinsicHeight;
      if (key.maxWidthPx != null && width > key.maxWidthPx!) {
        height = (height * key.maxWidthPx! / width).round();
        width = key.maxWidthPx!;
      }
      if (key.maxHeightPx != null && height > key.maxHeightPx!) {
        width = (width * key.maxHeightPx! / height).round();
        height = key.maxHeightPx!;
      }
      return TargetImageSize(width: width, height: height);
    });
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImage &&
      other.url == url &&
      other.maxWidthPx == maxWidthPx &&
      other.maxHeightPx == maxHeightPx;

  @override
  int get hashCode => Object.hash(url, maxWidthPx, maxHeightPx);
}
