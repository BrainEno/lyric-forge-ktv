import 'dart:io';

import '../../domain/models/shared_audio_track.dart';
import 'http_media_hub_incoming_upload_handler.dart' show MediaHubJsonWriter;

/// Serves track artwork and byte-range-capable audio streams for Media Hub
/// HTTP requests.
class HttpMediaHubMediaResponder {
  final MediaHubJsonWriter _writeJson;

  const HttpMediaHubMediaResponder({required MediaHubJsonWriter writeJson})
    : _writeJson = writeJson;

  Future<void> serveArtwork(HttpRequest request, SharedAudioTrack track) async {
    final path = track.artworkPath;
    if (path == null || path.trim().isEmpty) {
      await _writeJson(request.response, HttpStatus.notFound, {
        'error': 'artwork_not_found',
      });
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      await _writeJson(request.response, HttpStatus.gone, {
        'error': 'artwork_missing',
      });
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.parse(
      _imageMimeTypeFor(path),
    );
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'private, max-age=3600',
    );
    request.response.contentLength = await file.length();
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> serveAudio(HttpRequest request, SharedAudioTrack track) async {
    final file = File(track.localPath);
    if (!await file.exists()) {
      await _writeJson(request.response, HttpStatus.gone, {
        'error': 'source_file_missing',
      });
      return;
    }

    final length = await file.length();
    final parsed = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      length,
    );

    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType = ContentType.parse(
      _mimeTypeFor(track.format),
    );
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'private, no-store',
    );

    if (!parsed.isValid) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$length',
      );
      await request.response.close();
      return;
    }

    final range = parsed.range;
    if (range == null) {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = length;

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.partialContent;
    request.response.contentLength = range.length;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ${range.start}-${range.endInclusive}/$length',
    );

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    await request.response.addStream(
      file.openRead(range.start, range.endInclusive + 1),
    );
    await request.response.close();
  }

  String _mimeTypeFor(String format) {
    switch (format.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      default:
        return 'application/octet-stream';
    }
  }

  String _imageMimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }

  MediaHubParsedRange _parseRange(String? header, int length) {
    if (header == null || header.isEmpty) {
      return const MediaHubParsedRange.none();
    }

    if (!header.startsWith('bytes=') || header.contains(',')) {
      return const MediaHubParsedRange.invalid();
    }

    final value = header.substring('bytes='.length);
    final separator = value.indexOf('-');
    if (separator < 0) {
      return const MediaHubParsedRange.invalid();
    }

    final startText = value.substring(0, separator).trim();
    final endText = value.substring(separator + 1).trim();

    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0 || length <= 0) {
        return const MediaHubParsedRange.invalid();
      }

      final clamped = suffixLength > length ? length : suffixLength;
      return MediaHubParsedRange.valid(
        MediaHubByteRange(length - clamped, length - 1),
      );
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= length) {
      return const MediaHubParsedRange.invalid();
    }

    var endInclusive = length - 1;
    if (endText.isNotEmpty) {
      final requestedEnd = int.tryParse(endText);
      if (requestedEnd == null || requestedEnd < start) {
        return const MediaHubParsedRange.invalid();
      }
      endInclusive = requestedEnd >= length ? length - 1 : requestedEnd;
    }

    return MediaHubParsedRange.valid(MediaHubByteRange(start, endInclusive));
  }
}

class MediaHubByteRange {
  final int start;
  final int endInclusive;

  const MediaHubByteRange(this.start, this.endInclusive);

  int get length => endInclusive - start + 1;
}

class MediaHubParsedRange {
  final bool isValid;
  final MediaHubByteRange? range;

  const MediaHubParsedRange.none() : isValid = true, range = null;

  const MediaHubParsedRange.invalid() : isValid = false, range = null;

  const MediaHubParsedRange.valid(this.range) : isValid = true;
}
