import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/seekable_progress_bar.dart';

void main() {
  testWidgets('shows position and duration labels', (tester) async {
    await tester.pumpWidget(
      _app(
        _state(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 100),
        ),
        (_) {},
      ),
    );

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('01:40'), findsOneWidget);
  });

  testWidgets('shows placeholder duration when duration is unknown', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_state(duration: null), (_) {}));

    expect(find.text('--:--'), findsOneWidget);
  });

  testWidgets('tapping seeks immediately to the tapped position', (
    tester,
  ) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      _app(
        _state(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 100),
        ),
        seeks.add,
      ),
    );

    await tester.tapAt(_pointAt(tester, 0.75));
    await tester.pump();

    expect(seeks, hasLength(1));
    expect(seeks.single.inMilliseconds, inInclusiveRange(74000, 76000));
  });

  testWidgets('dragging shows the live target time and seeks on release', (
    tester,
  ) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      _app(
        _state(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 100),
        ),
        seeks.add,
      ),
    );

    final gesture = await tester.startGesture(_pointAt(tester, 0.2));
    await tester.pump();

    // Pressing seeks once right away.
    expect(seeks, hasLength(1));
    expect(seeks.single.inMilliseconds, inInclusiveRange(19000, 21000));

    await gesture.moveTo(_pointAt(tester, 0.8));
    await tester.pump();

    // While dragging the target time is shown live and no extra seek is sent.
    expect(find.text('01:20'), findsNWidgets(2));
    expect(seeks, hasLength(1));

    await gesture.up();
    await tester.pump();

    expect(seeks, hasLength(2));
    expect(seeks.last.inMilliseconds, inInclusiveRange(79000, 81000));
  });

  testWidgets('hovering shows the time under the cursor', (tester) async {
    await tester.pumpWidget(
      _app(
        _state(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 100),
        ),
        (_) {},
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _pointAt(tester, 0.1));
    await tester.pump();
    await mouse.moveTo(_pointAt(tester, 0.6));
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget);

    await mouse.moveTo(const Offset(-10, -10));
    await tester.pump();
    expect(find.text('01:00'), findsNothing);

    await mouse.removePointer();
  });

  testWidgets('dragging is disabled without a duration', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_app(_state(duration: null), seeks.add));

    await tester.tapAt(_pointAt(tester, 0.5));
    await tester.pump();

    expect(seeks, isEmpty);
  });

  testWidgets('dragging is disabled when enabled is false', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeekableProgressBar(
            state: _state(
              position: const Duration(seconds: 30),
              duration: const Duration(seconds: 100),
            ),
            onSeek: seeks.add,
            enabled: false,
          ),
        ),
      ),
    );

    await tester.tapAt(_pointAt(tester, 0.5));
    await tester.pump();

    expect(seeks, isEmpty);
  });

  testWidgets('mini variant seeks without a label row', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeekableProgressBar.mini(
            state: _state(
              position: const Duration(seconds: 30),
              duration: const Duration(seconds: 100),
            ),
            onSeek: seeks.add,
          ),
        ),
      ),
    );

    expect(find.text('00:30'), findsNothing);

    await tester.tapAt(_pointAt(tester, 0.5));
    await tester.pump();

    expect(seeks, hasLength(1));
    expect(seeks.single.inMilliseconds, inInclusiveRange(49000, 51000));
  });
}

Widget _app(PlaybackState state, ValueChanged<Duration> onSeek) {
  return MaterialApp(
    home: Scaffold(
      body: SeekableProgressBar(state: state, onSeek: onSeek),
    ),
  );
}

/// 进度条轨道在组件顶部 [hitHeight] 高度内，取水平比例位置。
Offset _pointAt(WidgetTester tester, double fraction) {
  final rect = tester.getRect(find.byType(SeekableProgressBar));
  return Offset(rect.left + rect.width * fraction, rect.top + 12);
}

PlaybackState _state({Duration position = Duration.zero, Duration? duration}) {
  return PlaybackState(
    isPlaying: false,
    isBuffering: false,
    isCompleted: false,
    isLoading: false,
    position: position,
    duration: duration,
    bufferedPosition: Duration.zero,
    speed: 1,
    volume: 1,
  );
}
