import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/persistence/atomic_json_file.dart';
import '../../domain/models/media_hub_device_identity.dart';
import '../../domain/services/media_hub_device_identity_store.dart';

class FileMediaHubDeviceIdentityStore implements MediaHubDeviceIdentityStore {
  static const int _schemaVersion = 1;

  static final AtomicJsonValidator _isValidStoreJson =
      AtomicJsonFile.versioned(
        currentVersion: _schemaVersion,
        validate: _isValidPayloadJson,
      );

  static bool _isValidPayloadJson(Object? decoded) =>
      decoded is Map &&
      decoded['deviceId'] is String &&
      decoded['deviceId'].toString().trim().isNotEmpty &&
      decoded['discoveryKey'] is String &&
      decoded['discoveryKey'].toString().trim().isNotEmpty;

  static const String _fileName = 'media_hub_device_identity.json';

  final Directory? rootDirectory;
  final Uuid _uuid;

  FileMediaHubDeviceIdentityStore({this.rootDirectory, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  Future<File> _file() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + _fileName);
  }

  @override
  Future<MediaHubDeviceIdentity> loadOrCreate() async {
    final file = await _file();
    await AtomicJsonFile.recoverIfNeeded(file, validate: _isValidStoreJson);
    if (await file.exists() &&
        !await AtomicJsonFile.isValidJsonFile(
          file,
          validate: _isValidStoreJson,
        )) {
      throw FormatException(
        'The Media Hub device identity is invalid and no recoverable copy is available. ${file.path}',
      );
    }
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          return MediaHubDeviceIdentity.fromJson(decoded);
        }
      }
    } catch (_) {
      // Corrupt identity data is replaced with a new local identity below.
    }

    final identity = MediaHubDeviceIdentity(
      deviceId: _uuid.v4(),
      discoveryKey:
          _uuid.v4().replaceAll('-', '') + _uuid.v4().replaceAll('-', ''),
    );
    await AtomicJsonFile.write(
      file,
      jsonEncode(
        AtomicJsonFile.stampSchemaVersion(identity.toJson(), _schemaVersion),
      ),
      validate: _isValidStoreJson,
    );
    return identity;
  }
}
