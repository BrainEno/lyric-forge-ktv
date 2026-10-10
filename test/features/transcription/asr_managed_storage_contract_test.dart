import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all managed ASR writers use the shared root resolver', () async {
    final locator = await File('lib/core/services/service_locator.dart').readAsString();
    expect(locator, contains('asrManagedStorageService = LocalAsrManagedStorageService()'));
    expect(
      RegExp(r'managedRootResolver: asrManagedStorageService\.resolveRoot')
          .allMatches(locator)
          .length,
      4,
    );

    for (final path in [
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
      'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
      'lib/features/transcription/data/services/resilient_asr_runtime_manager.dart',
    ]) {
      final source = await File(path).readAsString();
      expect(source, contains('Future<Directory> Function()? managedRootResolver'));
      expect(source, contains('final injected = managedRootResolver'));
    }
  });

  test('desktop setup and Settings expose safe managed storage relocation',
      () async {
    final setup = await File(
      'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
    ).readAsString();
    final settings = await File(
      'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
    ).readAsString();
    final card = await File(
      'lib/features/transcription/presentation/widgets/asr_storage_preflight_card.dart',
    ).readAsString();

    expect(setup, contains('FilePicker.platform.getDirectoryPath'));
    expect(setup, contains('_managedStorageService.moveToParent(parent)'));
    expect(setup, contains('onChangeLocation:'));

    expect(settings, contains('FilePicker.platform.getDirectoryPath'));
    expect(settings, contains('_managedStorageService.moveToParent('));
    expect(settings, contains('_managedStorageService.moveToDefault('));
    expect(settings, contains('正在迁移'));
    expect(settings, contains('_settingsStore.save(repaired)'));
    expect(settings, contains('Icons.folder_open_rounded'));

    expect(card, contains('VoidCallback? onChangeLocation'));
    expect(card, contains('换一个磁盘 / 文件夹'));
    expect(card, contains('Icons.folder_open_rounded'));
    expect(card, isNot(contains('drive_file_move_outline_rounded')));
  });

  test('migration is copy-first and validates before switching the root',
      () async {
    final source = await File(
      'lib/features/transcription/data/services/local_asr_managed_storage_service.dart',
    ).readAsString();

    final copy = source.indexOf('await _copyTree(');
    final verify = source.indexOf('copiedStats.files != sourceStats.files');
    final promote = source.indexOf('await staging.rename(target.path)');
    final persist = source.indexOf('await _writeConfiguredRoot(target.path)');
    final deleteOld = source.indexOf('await source.delete(recursive: true)');

    expect(copy, greaterThanOrEqualTo(0));
    expect(verify, greaterThan(copy));
    expect(promote, greaterThan(verify));
    expect(persist, greaterThan(promote));
    expect(deleteOld, greaterThan(persist));
    expect(source, contains(".ASRRuntime.migrating-"));
    expect(source, contains('目标位置已经存在 LyricForge ASRRuntime 数据'));
    expect(source, contains('_pathsOverlap(source.path, target.path)'));
    expect(source, contains('目标位置不能位于当前 ASRRuntime 目录内部'));
  });
}
