import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_connection_store.dart';

class FileMediaHubConnectionStore implements MediaHubConnectionStore {
  static const String _fileName = 'media_hub_connection.json';

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(
      directory.path + Platform.pathSeparator + _fileName,
    );
  }

  @override
  Future<MediaHubConnection?> loadLastConnection() async {
    final file = await _file();
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return MediaHubConnection.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveConnection(MediaHubConnection connection) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(connection.toJson()),
      flush: true,
    );
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
