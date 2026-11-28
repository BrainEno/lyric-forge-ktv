import 'dart:io';

/// Callback used by Media Hub route handlers to write a JSON HTTP response.
typedef MediaHubJsonWriter =
    Future<void> Function(
      HttpResponse response,
      int statusCode,
      Map<String, dynamic> body,
    );
