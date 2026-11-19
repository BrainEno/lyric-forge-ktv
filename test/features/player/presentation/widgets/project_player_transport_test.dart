import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_error_banner.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/project_player_transport.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/transport_bar.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

final _at = DateTime(2026, 11, 26);

ProjectManifest _project({
  bool lyrics = true,
  String? artist = '歌手',
  String? album = '专辑',
}) {
  return ProjectManifest(
    id: 'p1',
    name: '夜曲',
    artist: artist,
    album: album,
    createdAt: _at,
    updatedAt: _at,
    audioAsset: const AudioAsset(originalPath: '/music/a.mp3', format: 'mp3'),
    lyricDocument: lyrics
        ? const LyricDocument(
            language: 'zh',
            lines: [
              LyricLine(
                text: '第一行',
                startTime: Duration.zero,
                endTime: Duration(seconds: 3),
              ),
            ],
          )
        : null,
  );
}

PlaybackItem _item(String id) => PlaybackItem(
  id: id,
  title: id,
  audioAsset: AudioAsset(originalPath: '/music/$id.mp3', format: 'mp3'),
);

class _Calls {
  final List<String> log = [];

  ProjectPlayerTransportActions get actions => ProjectPlayerTransportActions(
    onPlayPause: () => log.add('play'),
    onSeek: (position) => log.add('seek ${position.inSeconds}'),
    onSwitchSource: (source) => log.add('source ${source.name}'),
    onSkipPrevious: () => log.add('previous'),
    onSkipNext: () => log.add('next'),
    onModeChanged: (ktv) => log.add('ktv $ktv'),
    onOpenFullScreenKtv: () => log.add('fullscreen'),
  );
}

ProjectPlayerTransportState _state({
  ProjectManifest? project,
  PlaybackState playback = const PlaybackState.idle(),
  PlaybackSessionState session = const PlaybackSessionState(),
  List<AudioSourceType> sources = const [AudioSourceType.original],
  bool ktvMode = false,
}) {
  return ProjectPlayerTransportState(
    project: project ?? _project(),
    playback: playback,
    session: session,
    availableSources: sources,
    ktvMode: ktvMode,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required ProjectPlayerTransportState state,
  required ProjectPlayerTransportActions actions,
  required ProjectPlayerTransportLayout layout,
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final transport = ProjectPlayerTransport(
    state: state,
    actions: actions,
    layout: layout,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: layout == ProjectPlayerTransportLayout.sidePane
            ? SizedBox(width: 380, child: transport)
            : Column(children: [transport]),
      ),
    ),
  );
}

IconButton _button(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

void main() {
  group('ProjectPlayerTransportLayout.forSpec', () {
    test('wide windows get the side pane', () {
      final spec = AppResponsive.fromSize(const Size(1280, 900));
      expect(
        ProjectPlayerTransportLayout.forSpec(spec),
        ProjectPlayerTransportLayout.sidePane,
      );
    });

    test('short windows get the one-row header', () {
      final spec = AppResponsive.fromSize(const Size(900, 500));
      expect(
        ProjectPlayerTransportLayout.forSpec(spec),
        ProjectPlayerTransportLayout.shortHeader,
      );
    });

    test('anything else gets the header', () {
      final spec = AppResponsive.fromSize(const Size(400, 800));
      expect(
        ProjectPlayerTransportLayout.forSpec(spec),
        ProjectPlayerTransportLayout.header,
      );
      expect(ProjectPlayerTransportLayout.header.isCompact, isTrue);
      expect(ProjectPlayerTransportLayout.sidePane.isCompact, isFalse);
    });
  });

  test('source labels are Chinese', () {
    expect(AudioSourceType.values.map(ProjectPlayerTransport.sourceLabel), [
      '原声',
      '伴奏',
      '人声',
    ]);
  });

  testWidgets('the side pane shows the full identity and a large cover', (
    tester,
  ) async {
    await _pump(
      tester,
      state: _state(),
      actions: _Calls().actions,
      layout: ProjectPlayerTransportLayout.sidePane,
    );

    expect(find.text('夜曲'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(tester.getSize(find.byType(AppArtwork)).width, greaterThan(200));
    expect(find.text('全屏 KTV'), findsOneWidget);
  });

  testWidgets('the header keeps the album out and the cover small', (
    tester,
  ) async {
    await _pump(
      tester,
      state: _state(project: _project(artist: null)),
      actions: _Calls().actions,
      layout: ProjectPlayerTransportLayout.header,
      size: const Size(400, 800),
    );

    expect(find.text('专辑'), findsNothing);
    expect(find.text(ProjectPlayerTransport.unknownArtist), findsOneWidget);
    expect(tester.getSize(find.byType(AppArtwork)).width, 56);
    expect(find.text('全屏'), findsOneWidget);
  });

  testWidgets('the short header puts the controls beside the identity', (
    tester,
  ) async {
    await _pump(
      tester,
      state: _state(),
      actions: _Calls().actions,
      layout: ProjectPlayerTransportLayout.shortHeader,
      size: const Size(900, 500),
    );

    final titleY = tester.getCenter(find.text('夜曲')).dy;
    final playY = tester.getCenter(find.byTooltip(TransportBar.playTooltip)).dy;
    expect((titleY - playY).abs(), lessThan(24));
    expect(tester.getSize(find.byType(AppArtwork)).width, 48);
    // Short windows drop the artist line to save height.
    expect(find.text('歌手'), findsNothing);
  });

  for (final layout in ProjectPlayerTransportLayout.values) {
    testWidgets('${layout.name}: skip buttons follow the queue', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(
        tester,
        state: _state(
          session: PlaybackSessionState(
            queue: [_item('a'), _item('b')],
            currentIndex: 0,
          ),
        ),
        actions: calls.actions,
        layout: layout,
      );

      final previous = _button(tester, TransportBar.previousTooltip);
      expect(previous.onPressed, isNotNull);
      await tester.tap(find.byTooltip(TransportBar.playTooltip));
      await tester.tap(find.byTooltip(TransportBar.nextTooltip));
      await tester.tap(find.byTooltip(TransportBar.previousTooltip));
      expect(calls.log, ['play', 'next', 'previous']);
    });
  }

  testWidgets('skips are disabled without a queue', (tester) async {
    await _pump(
      tester,
      state: _state(),
      actions: _Calls().actions,
      layout: ProjectPlayerTransportLayout.header,
      size: const Size(400, 800),
    );

    expect(_button(tester, TransportBar.previousTooltip).onPressed, isNull);
    expect(_button(tester, TransportBar.nextTooltip).onPressed, isNull);
  });

  testWidgets('source chips appear only when there is a choice', (
    tester,
  ) async {
    final calls = _Calls();
    await _pump(
      tester,
      state: _state(),
      actions: calls.actions,
      layout: ProjectPlayerTransportLayout.sidePane,
    );
    expect(find.widgetWithText(ChoiceChip, '原声'), findsNothing);

    await _pump(
      tester,
      state: _state(
        sources: const [AudioSourceType.original, AudioSourceType.instrumental],
        playback: const PlaybackState.idle().copyWith(
          currentSource: AudioSourceType.original,
        ),
      ),
      actions: calls.actions,
      layout: ProjectPlayerTransportLayout.sidePane,
    );

    final original = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '原声'),
    );
    expect(original.selected, isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, '伴奏'));
    expect(calls.log, ['source instrumental']);
  });

  testWidgets('KTV needs lyrics', (tester) async {
    final calls = _Calls();
    await _pump(
      tester,
      state: _state(project: _project(lyrics: false)),
      actions: calls.actions,
      layout: ProjectPlayerTransportLayout.sidePane,
    );

    final ktv = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'KTV'),
    );
    expect(ktv.onSelected, isNull);
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '普通'));
    expect(calls.log, ['ktv false']);
  });

  testWidgets('with lyrics, KTV and full screen are one tap away', (
    tester,
  ) async {
    final calls = _Calls();
    await _pump(
      tester,
      state: _state(),
      actions: calls.actions,
      layout: ProjectPlayerTransportLayout.sidePane,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'KTV'));
    await tester.tap(find.text('全屏 KTV'));
    expect(calls.log, ['ktv true', 'fullscreen']);
  });

  testWidgets('a playback error shows the banner in every layout', (
    tester,
  ) async {
    for (final layout in ProjectPlayerTransportLayout.values) {
      await _pump(
        tester,
        state: _state(
          playback: const PlaybackState.idle().copyWith(error: '无法打开音频'),
        ),
        actions: _Calls().actions,
        layout: layout,
      );
      expect(
        find.byType(PlaybackErrorBanner),
        findsOneWidget,
        reason: '$layout',
      );
      expect(find.text('无法打开音频'), findsOneWidget);
    }
  });

  testWidgets('buffering shows the busy play button', (tester) async {
    await _pump(
      tester,
      state: _state(
        playback: const PlaybackState.idle().copyWith(isBuffering: true),
      ),
      actions: _Calls().actions,
      layout: ProjectPlayerTransportLayout.sidePane,
    );

    expect(find.byTooltip(TransportBar.busyTooltip), findsOneWidget);
  });
}
