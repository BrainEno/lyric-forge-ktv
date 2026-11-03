import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'desktop settings exposes the complete AI transcription management surface',
    () {
      final source = File(
        'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
      ).readAsStringSync();

      for (final label in const [
        '当前推荐方案',
        '当前实际模型',
        '安装状态',
        '托管环境占用空间',
        '安装目录',
        '重新检测',
        '校验并补齐缺失组件',
        'AsrExistingModelCard',
        '迁移当前环境到其他文件夹',
        '删除模型',
        '删除并重装模型',
        '质量方案',
        '高级设置',
        '手工选择模型路径和 runtime',
      ]) {
        expect(
          source,
          contains(label),
          reason: 'missing settings surface: $label',
        );
      }
    },
  );

  test('Settings is one of the app-wide destinations, not a library section', () {
    // The library shell used to carry its own rail with a Settings entry, which
    // put 设置 in two places once the app grew persistent navigation. Settings
    // now lives in the shell that renders on every screen.
    final destinations = File(
      'lib/core/navigation/app_destinations.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/features/player/presentation/screens/local_music_library_shell.dart',
    ).readAsStringSync();

    expect(destinations, contains("AppDestination.settings => '设置'"));
    expect(
      destinations,
      contains('AppDestination.settings => Routes.settings'),
    );
    // And the library no longer renders its own rail or bottom bar.
    expect(shell, isNot(contains('NavigationRail(')));
    expect(shell, isNot(contains('NavigationBar(')));
  });

  test(
    'settings and project recognition share the same persisted transcription store',
    () {
      final settings = File(
        'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
      ).readAsStringSync();
      final project = File(
        'lib/features/project/presentation/screens/project_detail_screen.dart',
      ).readAsStringSync();
      final workflow = File(
        'lib/features/transcription/data/services/local_project_transcription_workflow.dart',
      ).readAsStringSync();
      final services = File('lib/app/app_services.dart').readAsStringSync();
      final assembly = File(
        'lib/app/transcription_assembly.dart',
      ).readAsStringSync();

      expect(
        settings,
        contains('widget.dependencies.transcriptionSettingsStore'),
      );
      expect(settings, contains('await _settingsStore.save'));
      expect(
        assembly,
        contains(
          'transcriptionSettingsStore: services.transcriptionSettingsStore',
        ),
      );
      expect(
        project,
        contains('widget.dependencies.transcriptionSettingsStore'),
      );
      expect(project, isNot(contains('AppServices.instance')));
      expect(project, contains("label: const Text('识别环境与高级设置')"));
      expect(workflow, contains('final config = await _settingsStore.load()'));
      expect(
        services,
        contains('settingsStore: transcriptionSettingsStore'),
        reason: 'workflow must receive the same store instance exposed to UI',
      );
    },
  );
}
