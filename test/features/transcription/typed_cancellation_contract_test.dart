import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production code does not classify cancellations by exception text', () {
    final equality = RegExp(
      r'''(?:\.message\s*==\s*['"]歌词识别已取消['"]|['"]歌词识别已取消['"]\s*==\s*\w+\.message)''',
    );
    final contains = RegExp(
      r'''\.message\s*\.\s*contains\s*\(\s*['"][^'"]*取消''',
    );
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final content = file.readAsStringSync();
      expect(equality.hasMatch(content), isFalse, reason: file.path);
      expect(contains.hasMatch(content), isFalse, reason: file.path);
    }
  });
}
