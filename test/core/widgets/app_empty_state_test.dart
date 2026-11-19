import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('page density shows icon, title, message and actions', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host(
        AppEmptyState(
          icon: Icons.lyrics_outlined,
          title: '这个工程还没有歌词',
          message: '可以从这里手动建立第一行歌词。',
          actions: [
            FilledButton(
              onPressed: () => pressed++,
              child: const Text('添加第一行'),
            ),
          ],
        ),
      ),
    );

    expect(find.text('这个工程还没有歌词'), findsOneWidget);
    expect(find.text('可以从这里手动建立第一行歌词。'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.lyrics_outlined)).size, 56);

    await tester.tap(find.text('添加第一行'));
    expect(pressed, 1);
  });

  testWidgets('panel density is smaller and omits empty slots', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppEmptyState(
          icon: Icons.queue_music_rounded,
          title: '播放队列为空',
          density: AppEmptyStateDensity.panel,
        ),
      ),
    );

    expect(find.text('播放队列为空'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.queue_music_rounded)).size,
      36,
    );
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('long messages wrap inside the readable width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final message = '很长的说明文字' * 20;

    await tester.pumpWidget(
      _host(
        AppEmptyState(
          icon: Icons.search_off_rounded,
          title: '没有结果',
          message: message,
        ),
      ),
    );

    expect(
      tester.getSize(find.text(message)).width,
      lessThanOrEqualTo(AppEmptyState.maxContentWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero density frames a large tile, headline and footer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        AppEmptyState(
          density: AppEmptyStateDensity.hero,
          icon: Icons.library_music_rounded,
          title: '你的本地音乐',
          message: '先像普通播放器一样打开音乐。',
          actions: [FilledButton(onPressed: () {}, child: const Text('选择音乐'))],
          footer: TextButton(onPressed: () {}, child: const Text('进入歌词制作')),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.library_music_rounded)).size,
      closeTo(156 * 0.44, 0.01),
    );
    final title = tester.widget<Text>(find.text('你的本地音乐'));
    expect(title.style?.fontWeight, FontWeight.w900);
    expect(
      tester.getTopLeft(find.text('进入歌词制作')).dy,
      greaterThan(tester.getBottomLeft(find.text('选择音乐')).dy),
      reason: 'the footer sits under the actions',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero density scrolls instead of overflowing on short screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        AppEmptyState(
          density: AppEmptyStateDensity.hero,
          icon: Icons.library_music_rounded,
          title: '建立你的本地音乐库',
          message: '导入后自动读取标题、艺人、专辑和内嵌封面。' * 4,
          status: const CircularProgressIndicator(),
          actions: [
            FilledButton(onPressed: () {}, child: const Text('添加音乐文件夹')),
            OutlinedButton(onPressed: () {}, child: const Text('添加音乐文件')),
          ],
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.library_music_rounded)).size,
      closeTo(92 * 0.44, 0.01),
      reason: 'short screens use the smallest tile',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status shows between the message and the actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: '无法打开',
          message: '请换一个文件再试。',
          status: const Text('文件格式不受支持'),
          actions: [FilledButton(onPressed: () {}, child: const Text('重试'))],
        ),
      ),
    );

    final status = tester.getCenter(find.text('文件格式不受支持')).dy;
    expect(status, greaterThan(tester.getCenter(find.text('请换一个文件再试。')).dy));
    expect(status, lessThan(tester.getCenter(find.text('重试')).dy));
  });

  group('inline density', () {
    Widget inline({double width = 900, bool withAction = true}) => _host(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: AppEmptyState(
            density: AppEmptyStateDensity.inline,
            icon: Icons.headphones_rounded,
            title: '还没有播放记录',
            message: '打开一首本地音乐后，会从这里快速继续。',
            footer: const Text('也可以从音乐库开始'),
            actions: [
              if (withAction)
                OutlinedButton(onPressed: () {}, child: const Text('选择音乐')),
            ],
          ),
        ),
      ),
    );

    testWidgets('puts the action at the end of the row on wide cards', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(inline());

      final title = tester.getCenter(find.text('还没有播放记录'));
      final action = tester.getCenter(find.text('选择音乐'));
      expect(action.dx, greaterThan(title.dx));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.headphones_rounded)).size,
        42,
      );
      expect(find.text('也可以从音乐库开始'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks the action under the text on narrow cards', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(inline(width: 360));

      final message = tester.getBottomLeft(find.text('打开一首本地音乐后，会从这里快速继续。'));
      final action = tester.getTopLeft(find.text('选择音乐'));
      expect(action.dy, greaterThan(message.dy));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.headphones_rounded)).size,
        36,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks the title as a heading and works without actions', (
      tester,
    ) async {
      await tester.pumpWidget(inline(withAction: false));

      expect(find.byType(OutlinedButton), findsNothing);
      expect(
        find.ancestor(
          of: find.text('还没有播放记录'),
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.header == true,
          ),
        ),
        findsOneWidget,
      );
    });

    test('stacking follows the card width, not the window', () {
      expect(
        AppEmptyState.inlineStacksActions(
          AppResponsive.fromSize(const Size(360, 200)),
        ),
        isTrue,
      );
      expect(
        AppEmptyState.inlineStacksActions(
          AppResponsive.fromSize(const Size(900, 200)),
        ),
        isFalse,
      );
    });
  });
}
