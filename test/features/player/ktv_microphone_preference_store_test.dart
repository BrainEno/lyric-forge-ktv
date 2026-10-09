import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_ktv_microphone_preference_store.dart';

void main() {
  late Directory root;
  late FileKtvMicrophonePreferenceStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ktv-mic-pref-test-');
    store = FileKtvMicrophonePreferenceStore(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('persists and restores a normalized microphone device id', () async {
    await store.savePreferredInputDeviceId('  usb-mic-42  ');

    expect(await store.loadPreferredInputDeviceId(), 'usb-mic-42');
  });

  test('saving system default clears a previous device preference', () async {
    await store.savePreferredInputDeviceId('usb-mic');
    expect(await store.loadPreferredInputDeviceId(), 'usb-mic');

    await store.savePreferredInputDeviceId(null);

    expect(await store.loadPreferredInputDeviceId(), isNull);
  });

  test('blank device id is treated as system default', () async {
    await store.savePreferredInputDeviceId('usb-mic');
    await store.savePreferredInputDeviceId('   ');

    expect(await store.loadPreferredInputDeviceId(), isNull);
  });

  test('corrupted preference file degrades to system default', () async {
    await store.savePreferredInputDeviceId('usb-mic');
    final files = root.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    await files.single.writeAsString('{broken-json');

    expect(await store.loadPreferredInputDeviceId(), isNull);
  });
}
