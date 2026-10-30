import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/persistence/atomic_json_file.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_connection_store.dart';

class FileMediaHubConnectionStore implements MediaHubConnectionStore {
  static const int _schemaVersion = 1;

  static final AtomicJsonValidator _isValidStoreJson =
      AtomicJsonFile.versioned(
        currentVersion: _schemaVersion,
        validate: _isValidPayloadJson,
      );

  static bool _isValidPayloadJson(Object? decoded) =>
      decoded is Map &&
      decoded['host'] is String &&
      decoded['host'].toString().isNotEmpty &&
      decoded['port'] is num &&
      decoded['token'] is String &&
      decoded['token'].toString().isNotEmpty;

  static const String _fileName = 'media_hub_connection.json';

  Future<void> _writeChain = Future<void>.value();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + _fileName);
  }

  @override
  Future<MediaHubConnection?> loadLastConnection() async {
    try {
      await _writeChain;
    } catch (_) {}
    final file = await _file();
    await AtomicJsonFile.recoverIfNeeded(file, validate: _isValidStoreJson);
    if (await file.exists() &&
        !await AtomicJsonFile.isValidJsonFile(
          file,
          validate: _isValidStoreJson,
        )) {
      throw FormatException(
        'The saved Media Hub connection is invalid and no recoverable copy is available. ${file.path}',
      );
    }
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
  Future<void> saveConnection(MediaHubConnection connection) {
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}

      final file = await _file();
      await AtomicJsonFile.write(
        file,
        jsonEncode(
          AtomicJsonFile.stampSchemaVersion(
            connection.toJson(),
            _schemaVersion,
          ),
        ),
        validate: _isValidStoreJson,
      );
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
        for (final sidecar in <File>[
          AtomicJsonFile.temporaryFor(file),
          AtomicJsonFile.backupFor(file),
          AtomicJsonFile.backupTemporaryFor(file),
          AtomicJsonFile.recoveryTemporaryFor(file),
          file,
        ]) {
          if (await sidecar.exists()) await sidecar.delete();
        }
      } catch (_) {
        // Forget is best-effort; a missing/unavailable cache should not block UI.
      }
    }();
    _writeChain = operation;
    return operation;
  }
}
