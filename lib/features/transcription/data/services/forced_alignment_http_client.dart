import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'qwen_native_runtime_session.dart';

/// A separate client for an explicit arbitrary-text alignment API.
///
/// Qwen's `/v1/transcribe` endpoint is ASR, not a forced-alignment endpoint.
/// Production callers supply the active pinned Qwen runtime [session]. This
/// client never sends alignment text to `/v1/transcribe` or treats ASR context
/// as forced alignment.
class ForcedAlignmentHttpClient {
  final Uri endpoint;
  final HttpClient _httpClient;
  final QwenNativeRuntimeSession _session;
  final Duration requestTimeout;
  HttpClientRequest? _activeRequest;

  ForcedAlignmentHttpClient({
    required this.endpoint,
    required QwenNativeRuntimeSession session,
    this.requestTimeout = const Duration(minutes: 5),
  }) : _session = session,
       _httpClient = _createPinnedHttpClient(
         session: session,
         endpoint: endpoint,
         requestTimeout: requestTimeout,
       );

  /// Aligns [text] against [audioPath], validating all returned spans.
  ///
  /// The expected bridge request is `{audio, text, language}`. The response
  /// may be `{items: [...]}` or `{results: [{items: [...] }]}`, matching the
  /// official Qwen result shape. Each item must expose text, start_time and
  /// end_time in seconds.
  Future<List<ForcedAlignedSpan>> align({
    required String audioPath,
    required String text,
    required String language,
    required Duration audioDuration,
  }) async {
    if (audioPath.trim().isEmpty) {
      throw ArgumentError.value(audioPath, 'audioPath', 'Must not be empty.');
    }
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }
    if (language.trim().isEmpty) {
      throw ArgumentError.value(language, 'language', 'Must not be empty.');
    }
    if (audioDuration <= Duration.zero) {
      throw ArgumentError.value(
        audioDuration,
        'audioDuration',
        'Must be positive.',
      );
    }

    final stopwatch = Stopwatch()..start();
    HttpClientRequest? request;
    try {
      request = await _httpClient
          .postUrl(endpoint)
          .timeout(_remainingTimeout(stopwatch));
      _activeRequest = request;
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      _session.authorize(request);
      request.write(
        jsonEncode({'audio': audioPath, 'text': text, 'language': language}),
      );

      final response = await request.close().timeout(
        _remainingTimeout(stopwatch),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_remainingTimeout(stopwatch));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ForcedAlignmentException(
          'Forced-alignment endpoint returned HTTP ${response.statusCode}.',
        );
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        throw const ForcedAlignmentException(
          'Forced-alignment endpoint returned invalid JSON.',
        );
      }

      final items = _extractItems(decoded);
      if (items.isEmpty) {
        throw const ForcedAlignmentException(
          'Forced-alignment endpoint returned no aligned spans.',
        );
      }

      final spans = <ForcedAlignedSpan>[];
      var previousStart = Duration.zero;
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item is! Map<String, dynamic>) {
          throw ForcedAlignmentException(
            'Aligned span $index is not an object.',
          );
        }
        final spanText = item['text'];
        final startSeconds = _seconds(item['start_time'] ?? item['start']);
        final endSeconds = _seconds(item['end_time'] ?? item['end']);
        if (spanText is! String || spanText.trim().isEmpty) {
          throw ForcedAlignmentException('Aligned span $index has empty text.');
        }
        if (startSeconds == null || endSeconds == null) {
          throw ForcedAlignmentException(
            'Aligned span $index has invalid timestamps.',
          );
        }
        if (startSeconds < 0 || endSeconds <= startSeconds) {
          throw ForcedAlignmentException(
            'Aligned span $index has a negative or empty interval.',
          );
        }
        final start = Duration(microseconds: (startSeconds * 1000000).round());
        final end = Duration(microseconds: (endSeconds * 1000000).round());
        if (start < previousStart) {
          throw ForcedAlignmentException(
            'Aligned spans are not ordered by start time at index $index.',
          );
        }
        if (end > audioDuration) {
          throw ForcedAlignmentException(
            'Aligned span $index exceeds the audio duration.',
          );
        }
        spans.add(ForcedAlignedSpan(text: spanText, start: start, end: end));
        previousStart = start;
      }
      return List.unmodifiable(spans);
    } on TimeoutException catch (error) {
      final activeRequest = _activeRequest;
      if (activeRequest != null) {
        activeRequest.abort(error, StackTrace.current);
      }
      _httpClient.close(force: true);
      throw ForcedAlignmentException(
        'Forced-alignment request timed out after '
        '${requestTimeout.inSeconds} seconds.',
      );
    } on HandshakeException {
      request?.abort();
      throw const ForcedAlignmentException(
        'Forced-alignment server identity verification failed.',
      );
    } on IOException catch (error) {
      request?.abort(error, StackTrace.current);
      throw ForcedAlignmentException(
        'Forced-alignment HTTP request was interrupted: '
        '${_session.redact(error.toString())}',
      );
    } finally {
      if (identical(_activeRequest, request)) _activeRequest = null;
    }
  }

  Duration _remainingTimeout(Stopwatch stopwatch) {
    final remaining = requestTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'Forced-alignment request exceeded its overall deadline.',
        requestTimeout,
      );
    }
    return remaining;
  }

  List<dynamic> _extractItems(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const ForcedAlignmentException(
        'Forced-alignment response must be a JSON object.',
      );
    }
    final directItems = decoded['items'];
    if (directItems is List) return directItems;

    final results = decoded['results'];
    if (results is List && results.isNotEmpty) {
      final first = results.first;
      if (first is Map<String, dynamic> && first['items'] is List) {
        return first['items'] as List<dynamic>;
      }
    }
    throw const ForcedAlignmentException(
      'Response must contain items or results[0].items.',
    );
  }

  double? _seconds(dynamic value) {
    final seconds = value is num ? value.toDouble() : double.tryParse('$value');
    if (seconds == null || !seconds.isFinite) return null;
    return seconds;
  }

  void close({bool force = false}) {
    if (force) {
      final request = _activeRequest;
      _activeRequest = null;
      request?.abort();
    }
    _httpClient.close(force: force);
  }
}

HttpClient _createPinnedHttpClient({
  required QwenNativeRuntimeSession session,
  required Uri endpoint,
  required Duration requestTimeout,
}) {
  if (endpoint != session.endpoint('/v1/align')) {
    throw ArgumentError.value(
      endpoint,
      'endpoint',
      'Must be the active Qwen session alignment URI.',
    );
  }
  if (requestTimeout <= Duration.zero) {
    throw ArgumentError.value(
      requestTimeout,
      'requestTimeout',
      'Must be positive.',
    );
  }
  return session.createHttpClient(connectionTimeout: requestTimeout);
}

class ForcedAlignmentException implements Exception {
  final String message;

  const ForcedAlignmentException(this.message);

  @override
  String toString() => 'ForcedAlignmentException: $message';
}
