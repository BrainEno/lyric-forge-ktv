import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'online_lyric_endpoints.dart';

/// Fetches one text response; the seam the lyric sources are tested through.
typedef OnlineLyricHttpGet =
    Future<String> Function(Uri uri, {Map<String, String> headers});

/// A lyric site answered with an error status.
class OnlineLyricHttpException implements Exception {
  final int statusCode;
  final Uri uri;

  const OnlineLyricHttpException(this.statusCode, this.uri);

  @override
  String toString() => 'HTTP $statusCode（${uri.host}）';
}

/// [OnlineLyricHttpGet] over `dart:io`.
///
/// [createClient] lets the app reuse the proxy settings of the model
/// downloads; every request gets its own client, closed afterwards.
class IoOnlineLyricHttp {
  final Future<HttpClient> Function() _createClient;
  final Duration timeout;

  IoOnlineLyricHttp({
    Future<HttpClient> Function()? createClient,
    this.timeout = const Duration(seconds: 10),
  }) : _createClient = createClient ?? _defaultClient;

  static Future<HttpClient> _defaultClient() async =>
      HttpClient()..connectionTimeout = const Duration(seconds: 8);

  Future<String> get(Uri uri, {Map<String, String> headers = const {}}) async {
    final client = await _createClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        OnlineLyricEndpoints.userAgent,
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OnlineLyricHttpException(response.statusCode, uri);
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
