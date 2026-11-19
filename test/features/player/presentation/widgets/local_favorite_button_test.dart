import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_pulse.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/local_collection_actions.dart';

/// A collection store whose writes finish only when the test says so.
class _Collections implements LocalMediaCollectionRepository {
  _Collections({this.favorite = false});

  bool favorite;
  Completer<bool>? pendingWrite;
  final StreamController<int> _changes = StreamController<int>.broadcast();
  var writes = 0;

  @override
  Stream<int> get changes => _changes.stream;

  @override
  Future<bool> isFavorite(String sourcePath) async => favorite;

  @override
  Future<bool> toggleFavorite(String sourcePath) {
    writes++;
    final write = Completer<bool>();
    pendingWrite = write;
    return write.future;
  }

  /// Lets the pending write land, as the store would.
  Future<void> finishWrite() async {
    favorite = !favorite;
    pendingWrite!.complete(favorite);
    _changes.add(1);
  }

  void failWrite() {
    pendingWrite!.completeError(StateError('只读'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _Collections collections) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: LocalFavoriteButton(
            sourcePath: '/music/song.flac',
            repository: collections,
          ),
        ),
      ),
    ),
  );
  // Settle: the load lands on the next frame, and the button then animates
  // its icon colour from the disabled grey.
  await tester.pumpAndSettle();
}

IconButton _button(WidgetTester tester) =>
    tester.widget<IconButton>(find.byType(IconButton));

Color _heartColour(WidgetTester tester, IconData icon) {
  final text = tester.widget<RichText>(
    find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
  );
  return text.text.style!.color!;
}

double _heartScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(AppTapPulse),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getMaxScaleOnAxis();
}

void main() {
  testWidgets('fills at once, before the store has written', (tester) async {
    final collections = _Collections();
    await _pump(tester, collections);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(collections.writes, 1);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    // It used to grey out while it waited.
    expect(_button(tester).onPressed, isNotNull);

    await collections.finishWrite();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('a filled heart takes the accent', (tester) async {
    final collections = _Collections(favorite: true);
    await _pump(tester, collections);

    expect(_button(tester).isSelected, isTrue);
    expect(_heartColour(tester, Icons.favorite_rounded), AppColors.accent);
  });

  testWidgets('an empty heart stays grey', (tester) async {
    await _pump(tester, _Collections());

    expect(_button(tester).isSelected, isFalse);
    expect(
      _heartColour(tester, Icons.favorite_border_rounded),
      isNot(AppColors.accent),
    );
  });

  testWidgets('the heart pulses when it fills', (tester) async {
    final collections = _Collections();
    await _pump(tester, collections);
    expect(_heartScale(tester), closeTo(1, 1e-9));

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_heartScale(tester), greaterThan(1.05));
    await collections.finishWrite();
    await tester.pumpAndSettle();
    expect(_heartScale(tester), closeTo(1, 1e-9));
  });

  testWidgets('emptying the heart does not pulse', (tester) async {
    final collections = _Collections(favorite: true);
    await _pump(tester, collections);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(_heartScale(tester), closeTo(1, 1e-9));
    await collections.finishWrite();
    await tester.pumpAndSettle();
  });

  testWidgets('every press clicks', (tester) async {
    final calls = <String?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String?);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final collections = _Collections();
    await _pump(tester, collections);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await collections.finishWrite();
    await tester.pumpAndSettle();

    expect(calls, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('a second press while writing is ignored', (tester) async {
    final collections = _Collections();
    await _pump(tester, collections);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(collections.writes, 1);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await collections.finishWrite();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed write puts the heart back and explains', (
    tester,
  ) async {
    final collections = _Collections();
    await _pump(tester, collections);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    collections.failWrite();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.textContaining('收藏未保存'), findsOneWidget);
  });

  testWidgets('stays disabled until it knows the state', (tester) async {
    final collections = _Collections();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalFavoriteButton(
            sourcePath: '/music/song.flac',
            repository: collections,
          ),
        ),
      ),
    );

    // First frame: the load has not answered yet.
    expect(_button(tester).onPressed, isNull);
    await tester.pump();
    expect(_button(tester).onPressed, isNotNull);
  });
}
