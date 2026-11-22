import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/project_sung_language_selector.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/spoken_language.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? value,
  String? recognizedAs,
  ValueChanged<String?>? onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        child: ProjectSungLanguageSelector(
          value: value,
          recognizedAs: recognizedAs,
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);

String _hint(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('project_sung_language_hint')))
    .data!;

void main() {
  test('offers 自动判断, the listed languages and an older setting', () {
    expect(ProjectSungLanguageSelector.options(null), [
      null,
      ...SpokenLanguagePolicy.selectableLanguages,
    ]);
    expect(ProjectSungLanguageSelector.options('it').last, 'it');
    expect(
      ProjectSungLanguageSelector.options('en'),
      hasLength(SpokenLanguagePolicy.selectableLanguages.length + 1),
    );
    expect(ProjectSungLanguageSelector.labelOf(null), '自动判断');
    expect(ProjectSungLanguageSelector.labelOf('en'), '英文');
  });

  testWidgets('the hint says what the setting does', (tester) async {
    await _pump(tester, onChanged: (_) {});
    expect(find.text('自动判断'), findsOneWidget);
    expect(_hint(tester), '识别时先听演唱部分再定语言');

    await _pump(tester, recognizedAs: '挪威语（引擎检测）', onChanged: (_) {});
    expect(_hint(tester), '上次识别：挪威语（引擎检测）');

    await _pump(tester, value: 'en', recognizedAs: '挪威语', onChanged: (_) {});
    expect(find.text('英文'), findsOneWidget);
    expect(_hint(tester), '这首歌固定按英文识别，不受识别设置影响');
  });

  testWidgets('choosing reports the code, and 自动判断 as null', (tester) async {
    final chosen = <String?>[];
    await _pump(tester, onChanged: chosen.add);

    await tester.tap(find.byKey(const ValueKey('project_sung_language_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_sung_language_en')));
    await tester.pumpAndSettle();

    await _pump(tester, value: 'en', onChanged: chosen.add);
    await tester.tap(find.byKey(const ValueKey('project_sung_language_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_sung_language_auto')));
    await tester.pumpAndSettle();

    expect(chosen, ['en', null]);
  });

  testWidgets('disabled while recognising', (tester) async {
    await _pump(tester, value: 'ja');
    await tester.tap(find.byKey(const ValueKey('project_sung_language_menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('project_sung_language_en')),
      findsNothing,
    );
  });
}
