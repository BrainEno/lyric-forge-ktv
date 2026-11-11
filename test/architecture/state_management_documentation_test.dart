import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final playerArchitecture = File('docs/architecture_player.md').readAsStringSync();
  final decisions = File('docs/decisions.md').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final editor = File('lib/features/lyrics/presentation/screens/lyric_editor_screen.dart').readAsStringSync();
  final controller = File('lib/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart').readAsStringSync();

  group('state management documentation (#235)', () {
    test('documents the dependency actually declared in pubspec', () {
      expect(pubspec, matches(RegExp(r'^\s+provider:\s*\^6\.1\.2', multiLine: true)));
      expect(playerArchitecture, contains('provider: ^6.1.2'));
      expect(playerArchitecture, isNot(contains('未采用 BLoC 或任何第三方状态管理框架')));
      expect(playerArchitecture, isNot(contains('无第三方状态框架')));
    });

    test('documents current editor provider and observable controller', () {
      expect(editor, contains("import 'package:provider/provider.dart'"));
      expect(editor, contains('ChangeNotifierProvider'));
      expect(controller, contains('ChangeNotifier'));
      expect(playerArchitecture, contains('Provider/Selector'));
      expect(playerArchitecture, contains('ChangeNotifier'));
    });

    test('records the source of truth and assembly responsibilities', () {
      expect(playerArchitecture, contains('PlaybackSessionService'));
      expect(playerArchitecture, contains('唯一事实源'));
      expect(playerArchitecture, contains('组合根'));
      expect(playerArchitecture, contains('构造参数'));
      expect(playerArchitecture, contains('service locator'));
      expect(Directory('lib/app').existsSync(), isTrue);
      expect(File('lib/core/services/service_locator.dart').existsSync(), isFalse);
    });

    test('decision explains alternatives, lifecycle and error ownership', () {
      final start = decisions.indexOf('## D-013 ');
      expect(start, greaterThanOrEqualTo(0));
      final next = decisions.indexOf('\n## ', start + 1);
      final section = decisions.substring(start, next == -1 ? null : next);
      for (final term in ['setState', 'Stream', 'ChangeNotifier', 'Provider', 'Selector', '生命周期', '释放', '错误', '取消', '事实源', 'lib/app/', 'domain', '测试', '状态：生效']) {
        expect(section, contains(term), reason: 'D-013 must describe $term');
      }
    });
  });
}
