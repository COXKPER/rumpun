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
      final client = HttpClient();
      try {
        final response = await client.getUrl(Uri.parse(key.url))
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
        // Bump the in-memory cap before writing big files; the default 100 MiB
        // evicts aggressively while scrolling feeds.
        PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
        await file.writeAsBytes(bytes, flush: false);
      } finally {
        client.close(force: true);
      }
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
