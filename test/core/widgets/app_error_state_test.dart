import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';
import 'package:lyric_forge_ktv/core/widgets/app_error_state.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows a red icon, the text and a retry button', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _host(
        AppErrorState(
          title: '加载工程失败',
          message: '工程文件暂时无法读取，请重新加载。',
          onRetry: () => retried++,
        ),
      ),
    );

    expect(find.text('加载工程失败'), findsOneWidget);
    expect(find.text('工程文件暂时无法读取，请重新加载。'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded));
    expect(icon.color, AppColors.error);
    expect(icon.size, 56);

    await tester.tap(find.text(AppErrorState.defaultRetryLabel));
    expect(retried, 1);
  });

  testWidgets('the retry button keeps the touch-target height', (tester) async {
    await tester.pumpWidget(
      _host(AppErrorState(title: '加载失败', retryLabel: '重新加载', onRetry: () {})),
    );

    final button = find.ancestor(
      of: find.text('重新加载'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(
      tester.getSize(button).height,
      greaterThanOrEqualTo(AppErrorState.retryButtonHeight),
    );
  });

  testWidgets('without a retry callback there is no button', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppErrorState(
          title: '媒体分类加载失败',
          density: AppEmptyStateDensity.panel,
        ),
      ),
    );

    expect(find.text('媒体分类加载失败'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded)).size,
      36,
    );
  });

  testWidgets('the failure is announced as a live region', (tester) async {
    await tester.pumpWidget(_host(const AppErrorState(title: '加载播放器失败')));

    final liveRegion = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.liveRegion == true,
    );
    expect(liveRegion, findsOneWidget);
    expect(
      find.descendant(of: liveRegion, matching: find.text('加载播放器失败')),
      findsOneWidget,
    );
  });

  testWidgets('empty states keep the tertiary icon colour', (tester) async {
    await tester.pumpWidget(
      _host(const AppEmptyState(icon: Icons.inbox_rounded, title: '暂无内容')),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.inbox_rounded)).color,
      AppColors.textTertiary,
    );
  });
}
