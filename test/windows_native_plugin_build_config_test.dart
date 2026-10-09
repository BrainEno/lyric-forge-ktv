import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner keeps strict warnings while native plugins use vendor-safe flags', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();

    final runnerIndex = cmake.indexOf('add_subdirectory("runner")');
    final pluginFlagsIndex = cmake.indexOf('add_compile_options(');
    final generatedPluginsIndex =
        cmake.indexOf('include(flutter/generated_plugins.cmake)');

    expect(runnerIndex, greaterThanOrEqualTo(0));
    expect(pluginFlagsIndex, greaterThan(runnerIndex));
    expect(generatedPluginsIndex, greaterThan(pluginFlagsIndex));

    expect(cmake, contains('/MP'));
    expect(cmake, contains('/utf-8'));
    expect(cmake, contains('/wd4819'));
    expect(cmake, contains('/wd4244'));
    expect(cmake, contains('/IGNORE:4075'));

    // Project-owned runner code must still use the strict warning policy.
    expect(
      cmake,
      contains(r'target_compile_options(${TARGET} PRIVATE /W4 /WX)'),
    );
  });
}
