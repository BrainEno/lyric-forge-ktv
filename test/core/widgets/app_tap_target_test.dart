import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_target.dart';

// AppTapTarget is how a card or row whose tap opens or plays something is
// read by a screen reader (audit A-04): one button with a sentence, instead
// of the loose words of its pieces.

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Semantics _semantics(WidgetTester tester) => tester.widget<Semantics>(
  find
      .descendant(
        of: find.byType(AppTapTarget),
        matching: find.byType(Semantics),
      )
      .first,
);

Widget _card({VoidCallback? onTap}) => InkWell(
  onTap: onTap,
  child: const SizedBox(
    width: 200,
    height: 80,
    child: Column(children: [Text('晴天'), Text('周杰伦 · 叶惠美')]),
  ),
);

void main() {
  group('join', () {
    test('uses the Chinese comma and skips empty parts', () {
      expect(AppTapTarget.join(['晴天', null, ' 周杰伦 ', '', '  ']), '晴天，周杰伦');
    });

    test('keeps the order of the parts', () {
      expect(AppTapTarget.join(['第 1 首', '晴天', '正在播放']), '第 1 首，晴天，正在播放');
    });

    test('nothing to say is an empty label', () {
      expect(AppTapTarget.join(const <String?>[]), isEmpty);
      expect(AppTapTarget.join([null, ' ']), isEmpty);
    });
  });

  group('actionsFor', () {
    test('keeps the order and drops unavailable actions', () {
      final calls = <String>[];
      final actions = AppTapTarget.actionsFor({
        '重命名': () => calls.add('rename'),
        '加入播放队列': null,
        '删除': () => calls.add('delete'),
      });

      expect(actions.keys.map((action) => action.label), ['重命名', '删除']);
      actions[const CustomSemanticsAction(label: '删除')]!();
      actions[const CustomSemanticsAction(label: '重命名')]!();
      expect(calls, ['delete', 'rename']);
    });

    test('no actions is an empty map', () {
      expect(AppTapTarget.actionsFor(const {}), isEmpty);
      expect(AppTapTarget.actionsFor(const {'下载': null}), isEmpty);
    });
  });

  group('semantics', () {
    testWidgets('reads the card once, as a button with a hint', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        AppTapTarget(
          label: '晴天，周杰伦',
          hint: '播放',
          onTap: () => taps++,
          child: _card(onTap: () => taps++),
        ),
      );

      expect(find.bySemanticsLabel('晴天，周杰伦'), findsOneWidget);
      // The pieces are not read a second time.
      expect(find.bySemanticsLabel('晴天'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('叶惠美')), findsNothing);

      final semantics = _semantics(tester);
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.enabled, isTrue);
      expect(semantics.properties.hint, '播放');
      expect(semantics.container, isTrue);
      expect(semantics.excludeSemantics, isTrue);

      semantics.properties.onTap!();
      expect(taps, 1);
      // Pointer use of the card is unchanged.
      await tester.tap(find.text('晴天'));
      expect(taps, 2);
      handle.dispose();
    });

    testWidgets('a disabled card says so and drops its tap and hint', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        AppTapTarget(
          label: '选择音频',
          hint: '选择文件',
          enabled: false,
          onTap: () => taps++,
          child: _card(),
        ),
      );

      final semantics = _semantics(tester);
      expect(semantics.properties.enabled, isFalse);
      expect(semantics.properties.onTap, isNull);
      expect(semantics.properties.hint, isNull);
      expect(taps, 0);
    });

    testWidgets('selected is only set for cards that can be current', (
      tester,
    ) async {
      await _pump(
        tester,
        Column(
          children: [
            AppTapTarget(label: '当前', selected: true, child: _card()),
            AppTapTarget(label: '其他', selected: false, child: _card()),
            AppTapTarget(label: '普通', child: _card()),
          ],
        ),
      );

      final all = tester
          .widgetList<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  const {'当前', '其他', '普通'}.contains(widget.properties.label),
            ),
          )
          .toList();
      expect(all.map((semantics) => semantics.properties.selected), [
        true,
        false,
        null,
      ]);
    });

    testWidgets('nested buttons become the card actions', (tester) async {
      final calls = <String>[];
      await _pump(
        tester,
        AppTapTarget(
          label: '通勤，24 首歌曲',
          actions: {
            '重命名': () => calls.add('rename'),
            '加入播放队列': null,
            '删除播放列表': () => calls.add('delete'),
          },
          child: _card(),
        ),
      );

      final actions = _semantics(tester).properties.customSemanticsActions!;
      expect(actions.keys.map((action) => action.label), ['重命名', '删除播放列表']);
      actions[const CustomSemanticsAction(label: '删除播放列表')]!();
      actions[const CustomSemanticsAction(label: '重命名')]!();
      expect(calls, ['delete', 'rename']);
    });

    testWidgets('a disabled card keeps its actions', (tester) async {
      var relinks = 0;
      await _pump(
        tester,
        AppTapTarget(
          label: '晴天，文件不可用',
          enabled: false,
          onTap: () {},
          actions: {'重新定位文件': () => relinks++},
          child: _card(),
        ),
      );

      final actions = _semantics(tester).properties.customSemanticsActions!;
      actions[const CustomSemanticsAction(label: '重新定位文件')]!();
      expect(relinks, 1);
    });

    testWidgets('no actions leaves the custom actions unset', (tester) async {
      await _pump(
        tester,
        AppTapTarget(
          label: '晴天',
          actions: const {'下载到手机': null},
          child: _card(),
        ),
      );

      expect(_semantics(tester).properties.customSemanticsActions, isNull);
    });

    testWidgets('value and long press are passed through', (tester) async {
      var presses = 0;
      await _pump(
        tester,
        AppTapTarget(
          label: '正在后台解析',
          value: '40%',
          onLongPress: () => presses++,
          child: _card(),
        ),
      );

      final semantics = _semantics(tester);
      expect(semantics.properties.value, '40%');
      semantics.properties.onLongPress!();
      expect(presses, 1);
    });

    testWidgets('container false joins the enclosing node', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Semantics(
          container: true,
          customSemanticsActions: {
            const CustomSemanticsAction(label: '上移'): () {},
          },
          child: AppTapTarget(
            label: '第 2 首，晴天',
            onTap: () {},
            container: false,
            child: _card(),
          ),
        ),
      );

      expect(_semantics(tester).container, isFalse);
      final node = tester.getSemantics(find.bySemanticsLabel('第 2 首，晴天'));
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.customAction), isTrue);
      handle.dispose();
    });
  });
}
