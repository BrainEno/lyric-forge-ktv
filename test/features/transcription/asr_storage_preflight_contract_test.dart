import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service locator wraps production runtime with storage guard', () {
    final locator = File('lib/core/services/service_locator.dart').readAsStringSync();

    expect(locator, contains('LocalAsrStoragePreflightService('));
    expect(locator, contains('StoragePreflightAsrRuntimeManager('));
    expect(locator, contains('asrStoragePreflightService'));
  });

  test('first-run setup shows storage budget and blocks insufficient install', () {
    final setup = File(
      'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
    ).readAsStringSync();

    expect(setup, contains('AsrStoragePreflightCard('));
    expect(setup, contains('_ensureStorageBeforeInstall()'));
    expect(setup, contains('storageBlocked'));
    expect(setup, contains("'空间不足'"));
  });

  test('settings shows storage budget and rechecks before install', () {
    final settings = File(
      'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
    ).readAsStringSync();

    expect(settings, contains('AsrStoragePreflightCard('));
    expect(settings, contains('_ensureStorageBeforeInstall(current)'));
    expect(settings, contains('storageBlocked'));
    expect(settings, contains("'空间不足'"));
  });

  test('storage card explains reusable partial files and shortfall', () {
    final card = File(
      'lib/features/transcription/presentation/widgets/asr_storage_preflight_card.dart',
    ).readAsStringSync();

    expect(card, contains('已存在可复用'));
    expect(card, contains('本次建议至少可用'));
    expect(card, contains('当前可用'));
    expect(card, contains("label: '还差'"));
    expect(card, contains('.part 断点'));
  });
}
