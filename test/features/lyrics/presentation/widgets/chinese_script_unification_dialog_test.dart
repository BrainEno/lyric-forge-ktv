import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/chinese_script_preference.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/chinese_script_unification_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_converter.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/chinese_script_unification_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument _document({Map<String, dynamic> metadata = const {}}) =>
    LyricDocument(
      language: 'zh',
      lines: [
        for (final (index, text) in const [
          '我爱你',
          '让我们一起唱',
          '頭髮飄在風裡',
          '你在哪里',
        ].indexed)
          LyricLine(
            id: 'l$index',
            text: text,
            startTime: Duration(seconds: index * 3),
            endTime: Duration(seconds: index * 3 + 2),
          ),
      ],
      metadata: metadata,
    );

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    Set<int> protectedIndices = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showChineseScriptUnificationDialog(
                  context,
                  document: _document(),
                  protectedIndices: protectedIndices,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('previews the automatic plan and returns it on confirm', (
    tester,
  ) async {
    ChineseScriptUnificationPlan? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await showChineseScriptUnificationDialog(
                  context,
                  document: _document(),
                  protectedIndices: const {},
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(ChineseScriptStrings.actionTitle), findsOneWidget);
    expect(find.text('将把 1 行转换为简体：'), findsOneWidget);
    expect(find.text('头发飘在风里'), findsOneWidget);
    expect(find.text('当前：简体 2 行，繁体 1 行，通用 1 行'), findsOneWidget);

    await tester.tap(find.text('转换 1 行'));
    await tester.pumpAndSettle();

    expect(confirmed, isNotNull);
    expect(confirmed!.target, ChineseScriptTarget.simplified);
    expect(confirmed!.changes.single.index, 2);
  });

  testWidgets('choosing a traditional target recomputes and warns', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.text('繁體（台灣）'));
    await tester.pumpAndSettle();

    expect(find.text('转换 3 行'), findsOneWidget);
    expect(find.text('我愛你'), findsOneWidget);
    expect(find.text('你在哪裡'), findsOneWidget);
    expect(find.text(ChineseScriptStrings.approximateNote), findsOneWidget);
  });

  testWidgets('manually edited lines are skipped unless opted in', (
    tester,
  ) async {
    await openDialog(tester, protectedIndices: {2});

    expect(find.text(ChineseScriptStrings.noop(
      ChineseScriptNoopReason.onlyProtectedLines,
    )), findsOneWidget);
    expect(find.text('无需转换'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('同时转换手动编辑过的行'));
    await tester.pumpAndSettle();

    expect(find.text('转换 1 行'), findsOneWidget);
  });

  testWidgets('cancel returns nothing', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text(ChineseScriptStrings.actionTitle), findsNothing);
  });

  test('opens with the target of the last recorded unification', () {
    expect(
      initialChineseScriptPreferenceFor(_document()),
      ChineseScriptPreference.auto,
    );
    expect(
      initialChineseScriptPreferenceFor(
        _document(
          metadata: {
            ChineseScriptUnificationService.metadataKey: {
              'target': 'traditionalHongKong',
              'revision': 'r',
            },
          },
        ),
      ),
      ChineseScriptPreference.traditionalHongKong,
    );
  });

  testWidgets('the proofreading menu offers the action', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(
              onProofreadV2: () {},
              onUnifyChineseScript: () => fired++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    expect(find.text('统一简繁字形'), findsOneWidget);
    expect(find.text('不需要参考歌词；先预览改动行数，默认跳过手动编辑过的行'), findsOneWidget);

    await tester.tap(find.text('统一简繁字形'));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });
}
