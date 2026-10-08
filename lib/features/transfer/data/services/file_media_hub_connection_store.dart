import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_connection_store.dart';

class FileMediaHubConnectionStore implements MediaHubConnectionStore {
  static const String _fileName = 'media_hub_connection.json';

  Future<void> _writeChain = Future<void>.value();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(
      directory.path + Platform.pathSeparator + _fileName,
    );
  }

  @override
  Future<MediaHubConnection?> loadLastConnection() async {
    try {
      await _writeChain;
      final file = await _file();
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return MediaHubConnection.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveConnection(MediaHubConnection connection) {
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}

      final file = await _file();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(connection.toJson()),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }();
    _writeChain = operation;
    return operation;
  }

  @override
  Future<void> clear() {
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}

      try {
        final file = await _file();
        if (await file.exists()) await file.delete();
        final temporary = File('${file.path}.tmp');
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Forget is best-effort; a missing/unavailable cache should not block UI.
      }
    }();
    _writeChain = operation;
    return operation;
  }
}
