import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_settings_store.dart';

class FileTranscriptionSettingsStore
    implements TranscriptionSettingsStore, TranscriptionDownloadProxyStore {
  static const String _fileName = 'transcription_settings.json';

  final Future<File> Function()? _fileResolver;

  FileTranscriptionSettingsStore({Future<File> Function()? fileResolver})
    : _fileResolver = fileResolver;

  Future<File> _file() async {
    final resolver = _fileResolver;
    if (resolver != null) return resolver();
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
      throw const TranscriptionException('本地歌词识别配置不完整');
    }
    final file = await _file();
    await file.writeAsString(jsonEncode(config.toJson()), flush: true);
  }

  @override
  Future<String?> loadDownloadProxy() async {
    final file = await _file();
    if (!await file.exists()) return null;

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    final proxy = decoded['downloadProxy'];
    return proxy is String ? proxy : null;
  }

  @override
  Future<void> saveDownloadProxy(String proxy) async {
    final file = await _file();
    Map<String, dynamic> settings = {};
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('本地识别设置文件格式无效');
      }
      settings = decoded;
    }
    settings['downloadProxy'] = proxy.trim();
    await file.writeAsString(jsonEncode(settings), flush: true);
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
