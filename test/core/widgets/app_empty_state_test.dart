import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
