import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/persistence/atomic_json_file.dart';
import '../../../../core/persistence/serial_write_queue.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_connection_store.dart';

class FileMediaHubConnectionStore implements MediaHubConnectionStore {
  static const int _schemaVersion = 1;

  static final AtomicJsonValidator _isValidStoreJson = AtomicJsonFile.versioned(
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

  final SerialWriteQueue _writes = SerialWriteQueue();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + _fileName);
  }

  @override
  Future<MediaHubConnection?> loadLastConnection() async {
    await _writes.idle;
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
    return _writes.run(() async {
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
    });
  }

  @override
  Future<void> clear() {
    return _writes.run(() async {
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
    });
  }
}
