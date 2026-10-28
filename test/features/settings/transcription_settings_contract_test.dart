import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop settings exposes the complete AI transcription management surface', () {
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
      '一键下载安装',
      '删除模型',
      '删除并重装模型',
      '质量方案',
      '高级设置',
      '手工选择模型路径和 runtime',
    ]) {
      expect(source, contains(label), reason: 'missing settings surface: $label');
    }
  });

  test('desktop rail has a Settings entry without changing mobile bottom navigation', () {
    final source = File(
      'lib/features/player/presentation/screens/local_music_library_shell.dart',
    ).readAsStringSync();

    expect(source, contains("label: Text('设置')"));
    expect(source, contains('Navigator.pushNamed(context, Routes.settings)'));
    expect(source, contains('static const _bottomDestinations'));
  });

  test('settings and project recognition share the same persisted transcription store', () {
    final settings = File(
      'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
    ).readAsStringSync();
    final project = File(
      'lib/features/project/presentation/screens/project_detail_screen.dart',
    ).readAsStringSync();
    final workflow = File(
      'lib/features/transcription/data/services/local_project_transcription_workflow.dart',
    ).readAsStringSync();
    final locator = File(
      'lib/core/services/service_locator.dart',
    ).readAsStringSync();

    expect(settings, contains('services.transcriptionSettingsStore'));
    expect(settings, contains('await _settingsStore.save'));
    expect(project, contains('ServiceLocatorGlobal.I.transcriptionSettingsStore'));
    expect(project, contains("label: const Text('识别环境与高级设置')"));
    expect(workflow, contains('final config = await _settingsStore.load()'));
    expect(
      locator,
      contains('settingsStore: transcriptionSettingsStore'),
      reason: 'workflow must receive the same store instance exposed to UI',
    );
  });
}
