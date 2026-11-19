import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/project_audio_sources_section.dart';

const _plain = AudioAsset(originalPath: '/song.mp3', format: 'mp3');

void main() {
  late List<bool> toggles;
  late int accompaniment;
  late int vocal;

  setUp(() {
    toggles = <bool>[];
    accompaniment = 0;
    vocal = 0;
  });

  Widget host({
    AudioAsset audio = _plain,
    bool expanded = false,
    bool busy = false,
    bool importing = false,
    bool importingVocal = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ProjectAudioSourcesSection(
          audio: audio,
          expanded: expanded,
          onExpandedChanged: toggles.add,
          busy: busy,
          isImportingStem: importing,
          isImportingVocal: importingVocal,
          onImportAccompaniment: () => accompaniment++,
          onImportVocal: () => vocal++,
        ),
      ),
    );
  }

  testWidgets('collapsed: one row with a summary, no buttons', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('伴奏与人声'), findsOneWidget);
    expect(find.text('可选：导入与原曲对齐的伴奏或人声'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.byKey(ProjectAudioSourcesSection.toggleKey));
    expect(toggles, [true]);
  });

  testWidgets('expanded: both imports call back and the row folds again', (
    tester,
  ) async {
    await tester.pumpWidget(host(expanded: true));

    await tester.tap(find.text('导入已有伴奏'));
    await tester.tap(find.text('导入已有人声'));
    expect(accompaniment, 1);
    expect(vocal, 1);
    expect(find.textContaining('应用不会自动分离或校准'), findsOneWidget);

    await tester.tap(find.byKey(ProjectAudioSourcesSection.toggleKey));
    expect(toggles, [false]);
  });

  testWidgets('existing tracks are offered as replacements', (tester) async {
    await tester.pumpWidget(
      host(
        expanded: true,
        audio: const AudioAsset(
          originalPath: '/song.mp3',
          instrumentalPath: '/backing.mp3',
          vocalPath: '/vocal.mp3',
          format: 'mp3',
        ),
      ),
    );

    expect(find.text('已有伴奏轨 · 已有人声轨'), findsOneWidget);
    expect(find.text('更换伴奏'), findsOneWidget);
    expect(find.text('更换人声'), findsOneWidget);
  });

  testWidgets('a running import keeps the buttons visible and locked', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(busy: true, importing: true, importingVocal: true),
    );

    // Collapsed by the user, but the progress label must stay on screen.
    expect(find.text('正在导入人声…'), findsOneWidget);
    expect(find.text('导入已有伴奏'), findsOneWidget);
    final buttons = tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(buttons, hasLength(2));
    expect(buttons.every((button) => button.onPressed == null), isTrue);

    await tester.tap(find.byKey(ProjectAudioSourcesSection.toggleKey));
    expect(toggles, isEmpty);
  });

  testWidgets('recognition in progress disables the imports', (tester) async {
    await tester.pumpWidget(host(expanded: true, busy: true));

    final buttons = tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(buttons, hasLength(2));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('announces itself as an expandable button', (tester) async {
    await tester.pumpWidget(host());

    bool isToggle(Widget widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.expanded != null;

    final toggle = find.byWidgetPredicate(isToggle);
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);

    await tester.pumpWidget(host(expanded: true));
    expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
  });

  test('summary names each track', () {
    expect(audioSourcesSummary(_plain), '可选：导入与原曲对齐的伴奏或人声');
    expect(
      audioSourcesSummary(_plain.copyWith(instrumentalPath: '/b.mp3')),
      '已有伴奏轨 · 没有人声轨',
    );
    expect(
      audioSourcesSummary(_plain.copyWith(vocalPath: '/v.mp3')),
      '没有伴奏轨 · 已有人声轨',
    );
  });
}
