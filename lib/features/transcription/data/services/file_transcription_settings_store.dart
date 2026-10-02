import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_settings_store.dart';

class FileTranscriptionSettingsStore implements TranscriptionSettingsStore {
  static const String _fileName = 'transcription_settings.json';

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + _fileName);
  }

  @override
  Future<TranscriptionConfig?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final config = TranscriptionConfig.fromJson(decoded);
      return config.isConfigured ? config : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(TranscriptionConfig config) async {
    if (!config.isConfigured) {
      throw const TranscriptionException('Whisper 配置不完整');
    }
    final file = await _file();
    await file.writeAsString(jsonEncode(config.toJson()), flush: true);
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A settings cache failure should not block the UI.
    }
  }
}
