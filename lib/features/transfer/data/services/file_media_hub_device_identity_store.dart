import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/media_hub_device_identity.dart';
import '../../domain/services/media_hub_device_identity_store.dart';

class FileMediaHubDeviceIdentityStore implements MediaHubDeviceIdentityStore {
  static const String _fileName = 'media_hub_device_identity.json';

  final Directory? rootDirectory;
  final Uuid _uuid;

  FileMediaHubDeviceIdentityStore({
    this.rootDirectory,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  Future<File> _file() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + _fileName);
  }

  @override
  Future<MediaHubDeviceIdentity> loadOrCreate() async {
    final file = await _file();
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
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(identity.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    return identity;
  }
}
