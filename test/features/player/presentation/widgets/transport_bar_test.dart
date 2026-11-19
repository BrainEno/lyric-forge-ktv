import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/transport_bar.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('previous, play and next call their callbacks', (tester) async {
    var previous = 0;
    var playPause = 0;
    var next = 0;
    await tester.pumpWidget(
      _host(
        TransportBar(
          isPlaying: false,
          onPlayPause: () => playPause++,
          onPrevious: () => previous++,
          onNext: () => next++,
        ),
      ),
    );

    expect(find.byTooltip(TransportBar.seekBackTooltip), findsNothing);
    expect(find.byTooltip(TransportBar.seekForwardTooltip), findsNothing);

    await tester.tap(find.byTooltip(TransportBar.previousTooltip));
    await tester.tap(find.byTooltip(TransportBar.playTooltip));
    await tester.tap(find.byTooltip(TransportBar.nextTooltip));
    expect((previous, playPause, next), (1, 1, 1));
  });

  testWidgets('seek buttons appear around the play button when set', (
    tester,
  ) async {
    var back = 0;
    var forward = 0;
    await tester.pumpWidget(
      _host(
        TransportBar(
          isPlaying: true,
          onPlayPause: () {},
          onSeekBack: () => back++,
          onSeekForward: () => forward++,
        ),
      ),
    );

    final backX = tester.getCenter(find.byIcon(Icons.replay_10_rounded)).dx;
    final playX = tester.getCenter(find.byIcon(Icons.pause_rounded)).dx;
    final forwardX = tester.getCenter(find.byIcon(Icons.forward_10_rounded)).dx;
    expect(backX, lessThan(playX));
    expect(playX, lessThan(forwardX));

    await tester.tap(find.byTooltip(TransportBar.seekBackTooltip));
    await tester.tap(find.byTooltip(TransportBar.seekForwardTooltip));
    expect((back, forward), (1, 1));
    expect(find.byTooltip(TransportBar.pauseTooltip), findsOneWidget);
  });

  testWidgets('missing skip callbacks disable the buttons', (tester) async {
    await tester.pumpWidget(
      _host(TransportBar(isPlaying: false, onPlayPause: () {})),
    );

    IconButton button(IconData icon) {
      return tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
      );
    }

    expect(button(Icons.skip_previous_rounded).onPressed, isNull);
    expect(button(Icons.skip_next_rounded).onPressed, isNull);
    expect(button(Icons.play_arrow_rounded).onPressed, isNotNull);
  });

  testWidgets('busy players show a spinner and block play', (tester) async {
    var playPause = 0;
    await tester.pumpWidget(
      _host(
        TransportBar(
          isPlaying: false,
          isBusy: true,
          onPlayPause: () => playPause++,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    await tester.tap(find.byTooltip(TransportBar.busyTooltip));
    expect(playPause, 0);
  });

  testWidgets('play button follows the layout and the compact flag', (
    tester,
  ) async {
    final wide = AppResponsive.fromSize(const Size(1440, 900));
    final phone = AppResponsive.fromSize(const Size(390, 844));

    Future<Size> playSize(AppLayoutSpec layout, {bool compact = false}) async {
      await tester.pumpWidget(
        _host(
          TransportBar(
            layout: layout,
            compact: compact,
            isPlaying: false,
            onPlayPause: () {},
          ),
        ),
      );
      return tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.play_arrow_rounded),
          matching: find.byType(IconButton),
        ),
      );
    }

    expect(await playSize(wide), Size.square(wide.primaryPlayerControlExtent));
    expect(
      await playSize(phone),
      Size.square(phone.primaryPlayerControlExtent),
    );
    expect(
      await playSize(wide, compact: true),
      const Size.square(TransportBar.minimumPlayExtent),
    );
    expect(TransportBar.playIconSizeFor(64), 35);
  });

  testWidgets('wrapping bars fit a narrow panel', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 200,
          child: TransportBar(
            wrap: true,
            isPlaying: false,
            onPlayPause: () {},
            onPrevious: () {},
            onNext: () {},
            onSeekBack: () {},
            onSeekForward: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(5));
  });
}
