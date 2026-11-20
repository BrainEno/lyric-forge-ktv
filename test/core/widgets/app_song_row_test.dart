import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';
import 'package:lyric_forge_ktv/core/widgets/app_song_row.dart';
import 'package:lyric_forge_ktv/core/widgets/app_vinyl_disc.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget row, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ListView(children: [row])),
    ),
  );
}

Finder _rowText(String text) =>
    find.descendant(of: find.byType(AppSongRow), matching: find.text(text));

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(_rowText(text)).style?.color;

const _cover = AppArtwork(path: null, borderRadius: AppArtwork.rowRadius);

void main() {
  group('pure rules', () {
    test('the spoken label adds the playback state in words', () {
      expect(
        AppSongRow.spokenLabel('晴天，周杰伦', AppSongRowPlayback.none),
        '晴天，周杰伦',
      );
      expect(
        AppSongRow.spokenLabel('晴天，周杰伦', AppSongRowPlayback.playing),
        '晴天，周杰伦，${AppSongRow.playingLabel}',
      );
      expect(
        AppSongRow.spokenLabel('晴天', AppSongRowPlayback.paused),
        '晴天，${AppSongRow.pausedLabel}',
      );
    });

    test('playbackFor marks only the current song', () {
      expect(
        AppSongRow.playbackFor(isCurrent: false, isPlaying: true),
        AppSongRowPlayback.none,
      );
      expect(
        AppSongRow.playbackFor(isCurrent: true, isPlaying: true),
        AppSongRowPlayback.playing,
      );
      expect(
        AppSongRow.playbackFor(isCurrent: true, isPlaying: false),
        AppSongRowPlayback.paused,
      );
    });

    test('the cover never drops under the touch minimum', () {
      final phone = AppResponsive.fromSize(const Size(390, 844));
      final wide = AppResponsive.fromSize(const Size(1400, 900));
      expect(
        AppSongRow.artworkExtentFor(phone),
        greaterThanOrEqualTo(phone.minimumInteractiveExtent),
      );
      expect(AppSongRow.artworkExtentFor(wide), AppSongRow.artworkExtent);
    });
  });

  group('layout', () {
    testWidgets('shows title, subtitle and a cover sized for the phone', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(title: '晴天', subtitle: '周杰伦 · 叶惠美', artwork: _cover),
      );

      expect(_rowText('晴天'), findsOneWidget);
      expect(_rowText('周杰伦 · 叶惠美'), findsOneWidget);
      final phone = AppResponsive.fromSize(const Size(390, 844));
      expect(
        tester.getSize(find.byType(AppArtwork)),
        Size.square(AppSongRow.artworkExtentFor(phone)),
      );
    });

    testWidgets('is at least 48 dp tall on a phone', (tester) async {
      await _pump(tester, const AppSongRow(title: '晴天'));

      expect(
        tester.getSize(find.byType(AppSongRow)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('a long title ellipsizes instead of overflowing at 320', (
      tester,
    ) async {
      await _pump(
        tester,
        AppSongRow(
          title: '很长很长的歌名' * 8,
          subtitle: '很长很长的艺人名' * 8,
          artwork: _cover,
          badges: const [AppSongRowBadge(icon: Icons.lyrics_rounded)],
          trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
        ),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(_rowText('很长很长的歌名' * 8));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a number stands in for the cover in a track list', (
      tester,
    ) async {
      await _pump(tester, const AppSongRow(title: '晴天', index: '7'));

      expect(_rowText('7'), findsOneWidget);
      expect(find.byType(AppArtwork), findsNothing);
    });

    testWidgets('a number and a cover sit side by side in a playlist', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(title: '晴天', index: '12', artwork: _cover),
      );

      final number = tester.getCenter(_rowText('12'));
      final cover = tester.getCenter(find.byType(AppArtwork));
      expect(number.dx, lessThan(cover.dx));
    });

    testWidgets('badges sit before the subtitle', (tester) async {
      await _pump(
        tester,
        const AppSongRow(
          title: '晴天',
          subtitle: '周杰伦',
          badges: [AppSongRowBadge(icon: Icons.lyrics_rounded)],
        ),
      );

      final badge = tester.getCenter(find.byIcon(Icons.lyrics_rounded));
      final subtitle = tester.getCenter(_rowText('周杰伦'));
      expect(badge.dx, lessThan(subtitle.dx));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.lyrics_rounded)).size,
        AppSongRowBadge.iconSize,
      );
    });

    testWidgets('a download in flight shows a brass progress bar', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(
          title: '晴天',
          showProgress: true,
          progress: 0.4,
          notice: '正在下载 40%',
        ),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.4);
      expect(bar.color, AppColors.vinylBrass);
      expect(_rowText('正在下载 40%'), findsOneWidget);
      expect(_colorOf(tester, '正在下载 40%'), AppColors.textTertiary);
    });

    testWidgets('an unknown size gives an indeterminate bar', (tester) async {
      await _pump(
        tester,
        const AppSongRow(title: '晴天', showProgress: true),
      );

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    });

    testWidgets('a failure notice is written in the readable red', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(title: '晴天', notice: '下载失败', noticeIsError: true),
      );

      expect(_colorOf(tester, '下载失败'), AppColors.errorText);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a card row sits on the elevated surface', (tester) async {
      await _pump(tester, const AppSongRow(title: '晴天', card: true));

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppSongRow),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppColors.bgElevated);
    });
  });

  group('now playing', () {
    testWidgets('the playing row is brass with rhythm bars on its cover', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(
          title: '晴天',
          subtitle: '周杰伦',
          artwork: _cover,
          playback: AppSongRowPlayback.playing,
        ),
      );

      expect(_colorOf(tester, '晴天'), AppColors.vinylBrass);
      expect(_colorOf(tester, '周杰伦'), AppColors.textSecondary);
      final bars = tester.widget<AppRhythmBars>(find.byType(AppRhythmBars));
      expect(bars.playing, isTrue);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppSongRow),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppColors.vinylBrassMuted);
    });

    testWidgets('a paused current song keeps its bars, at rest', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(
          title: '晴天',
          artwork: _cover,
          playback: AppSongRowPlayback.paused,
        ),
      );

      expect(
        tester.widget<AppRhythmBars>(find.byType(AppRhythmBars)).playing,
        isFalse,
      );
    });

    testWidgets('in a numbered list the bars replace the number', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSongRow(
          title: '晴天',
          index: '3',
          playback: AppSongRowPlayback.playing,
        ),
      );

      expect(_rowText('3'), findsNothing);
      expect(find.byType(AppRhythmBars), findsOneWidget);
    });

    testWidgets('other rows have no bars and plain colours', (tester) async {
      await _pump(
        tester,
        const AppSongRow(title: '晴天', subtitle: '周杰伦', artwork: _cover),
      );

      expect(find.byType(AppRhythmBars), findsNothing);
      expect(_colorOf(tester, '晴天'), AppColors.textPrimary);
      expect(_colorOf(tester, '周杰伦'), AppColors.textTertiary);
    });
  });

  group('unavailable', () {
    testWidgets('dims the row, says why and ignores taps', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          subtitle: '周杰伦',
          artwork: const AppArtwork.missing(borderRadius: AppArtwork.rowRadius),
          unavailable: true,
          onTap: () => taps++,
        ),
      );

      expect(_rowText('周杰伦'), findsNothing);
      expect(_rowText(AppSongRow.defaultUnavailableLabel), findsOneWidget);
      expect(
        _colorOf(tester, AppSongRow.defaultUnavailableLabel),
        AppColors.errorText,
      );
      expect(_colorOf(tester, '晴天'), AppColors.textTertiary);

      await tester.tap(_rowText('晴天'));
      expect(taps, 0);
    });

    testWidgets('can say more than the default', (tester) async {
      await _pump(
        tester,
        const AppSongRow(
          title: '晴天',
          unavailable: true,
          unavailableLabel: '文件不可用 · 引用仍保留',
        ),
      );

      expect(_rowText('文件不可用 · 引用仍保留'), findsOneWidget);
    });
  });

  group('input', () {
    testWidgets('a tap on the text plays, the trailing control stays its own', (
      tester,
    ) async {
      var plays = 0;
      var menus = 0;
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          onTap: () => plays++,
          trailing: IconButton(
            tooltip: '更多',
            onPressed: () => menus++,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ),
      );

      await tester.tap(_rowText('晴天'));
      await tester.tap(find.byTooltip('更多'));

      expect(plays, 1);
      expect(menus, 1);
    });

    testWidgets('a long press reaches its callback', (tester) async {
      var presses = 0;
      await _pump(
        tester,
        AppSongRow(title: '晴天', onTap: () {}, onLongPress: () => presses++),
      );

      await tester.longPress(_rowText('晴天'));
      expect(presses, 1);
    });
  });

  group('semantics', () {
    testWidgets('reads the row as one button with its state', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          subtitle: '周杰伦',
          artwork: _cover,
          playback: AppSongRowPlayback.playing,
          onTap: () {},
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^晴天'))),
        isSemantics(
          label: '晴天，周杰伦，${AppSongRow.playingLabel}',
          hint: AppSongRow.defaultHint,
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a caller label replaces the default one', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          subtitle: '周杰伦 · FLAC',
          semanticLabel: '晴天，周杰伦，有歌词',
          semanticHint: '继续播放',
          onTap: () {},
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('晴天，周杰伦，有歌词'));
      expect(node.hint, '继续播放');
      handle.dispose();
    });

    testWidgets('menu entries are offered as actions, without the null ones', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var removed = 0;
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          onTap: () {},
          semanticActions: {'加入播放队列': null, '从音乐库移除': () => removed++},
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('晴天'));
      final actions = node.getSemanticsData().customSemanticsActionIds!.map(
        (id) => CustomSemanticsAction.getAction(id)!.label,
      );
      expect(actions, ['从音乐库移除']);

      final id = node.getSemanticsData().customSemanticsActionIds!.single;
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id,
      );
      expect(removed, 1);
      handle.dispose();
    });

    testWidgets('an unavailable row reads as disabled but keeps its actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          unavailable: true,
          onTap: () {},
          semanticActions: {'重新定位文件': () {}},
        ),
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel('晴天，${AppSongRow.defaultUnavailableLabel}'),
      );
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.customSemanticsActionIds, hasLength(1));
      expect(data.hint, isEmpty);
      handle.dispose();
    });

    testWidgets('badges and bars are not read on their own', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AppSongRow(
          title: '晴天',
          artwork: _cover,
          playback: AppSongRowPlayback.playing,
          badges: const [AppSongRowBadge(icon: Icons.lyrics_rounded)],
          onTap: () {},
        ),
      );

      // Everything in the tap area folds into the one label.
      expect(find.bySemanticsLabel('晴天'), findsNothing);
      expect(
        find.bySemanticsLabel('晴天，${AppSongRow.playingLabel}'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
