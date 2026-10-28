import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/services/ktv_microphone_preference_store.dart';

class FileKtvMicrophonePreferenceStore
    implements KtvMicrophonePreferenceStore {
  static const String _fileName = 'ktv_microphone_preferences.json';
  static const String _preferredInputDeviceKey = 'preferredInputDeviceId';

  final Directory? rootDirectory;

  const FileKtvMicrophonePreferenceStore({this.rootDirectory});

  Future<File> _file() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + _fileName);
  }

  @override
  Future<String?> loadPreferredInputDeviceId() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded[_preferredInputDeviceKey];
      if (value is! String) return null;
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePreferredInputDeviceId(String? deviceId) async {
    final normalized = deviceId?.trim();
    final file = await _file();
    if (normalized == null || normalized.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }

    await file.writeAsString(
      jsonEncode(<String, Object>{
        'version': 1,
        _preferredInputDeviceKey: normalized,
      }),
      flush: true,
    );
  }
}
