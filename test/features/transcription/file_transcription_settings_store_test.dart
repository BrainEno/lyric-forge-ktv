import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/file_transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  late Directory directory;
  late FileTranscriptionSettingsStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lyric-forge-settings-');
    store = FileTranscriptionSettingsStore(
      fileResolver: () async => File(
        '${directory.path}${Platform.pathSeparator}transcription_settings.json',
      ),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists a download proxy without requiring complete ASR settings',
    () async {
      await store.saveDownloadProxy('http://127.0.0.1:10808');

      expect(await store.loadDownloadProxy(), 'http://127.0.0.1:10808');
      expect(await store.load(), isNull);
    },
  );

  test(
    'updating the proxy preserves a complete transcription configuration',
    () async {
      const config = TranscriptionConfig(
        mode: TranscriptionMode.whisperOnly,
        whisperExecutable: 'whisper-cli',
        modelPath: 'ggml-large-v3.bin',
      );
      await store.save(config);
      await store.saveDownloadProxy('http://127.0.0.1:10808');

      expect((await store.load())?.downloadProxy, 'http://127.0.0.1:10808');
    },
  );
}
