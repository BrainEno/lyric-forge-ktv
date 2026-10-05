import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/main.dart';

void main() {
  test('LyricForge app root remains constructible', () {
    const app = LyricForgeApp();

    expect(app, isA<StatelessWidget>());
  });
}
