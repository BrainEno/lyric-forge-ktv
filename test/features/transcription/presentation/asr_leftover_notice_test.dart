import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_existing_model_actions.dart';

const _nested = '/data/Models/LyricForge/ASRRuntime/LyricForge/ASRRuntime';

const _leftover = AsrRuntimeLeftover(
  path: _nested,
  kind: AsrRuntimeLeftoverKind.nestedCopy,
  bytes: 2 << 30,
  files: 6,
  missingInActive: [AsrRuntimeUnit.whisperModel],
);

AsrManagedStorageLocation _location([
  List<AsrRuntimeLeftover> leftovers = const [_leftover],
]) {
  return AsrManagedStorageLocation(
    activeRoot: '/data/Models/LyricForge/ASRRuntime',
    defaultRoot: '/support/LyricForge/ASRRuntime',
    managedBytes: 0,
    isDefault: false,
    leftovers: leftovers,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  test('the notice shows for leftovers or a message only', () {
    expect(AsrLeftoverNotice.showsFor(null, null), isFalse);
    expect(AsrLeftoverNotice.showsFor(_location(const []), null), isFalse);
    expect(AsrLeftoverNotice.showsFor(_location(), null), isTrue);
    expect(AsrLeftoverNotice.showsFor(_location(const []), '已清理'), isTrue);
  });

  testWidgets('lists each leftover and offers to merge and clean', (
    tester,
  ) async {
    var cleaned = 0;
    await _pump(
      tester,
      AsrLeftoverNotice(
        location: _location(),
        cleaning: false,
        onCleanUp: () => cleaned++,
      ),
    );

    expect(find.textContaining('可释放约 2.00 GB'), findsOneWidget);
    expect(find.textContaining(_nested), findsOneWidget);
    expect(find.textContaining('Whisper large-v3 模型'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('asr_leftover_clean_up')));
    expect(cleaned, 1);
  });

  testWidgets('the button is disabled while cleaning or busy', (tester) async {
    await _pump(
      tester,
      AsrLeftoverNotice(
        location: _location(),
        cleaning: true,
        onCleanUp: () {},
      ),
    );
    expect(find.text(AsrLeftoverText.cleaningLabel), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    var button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('asr_leftover_clean_up')),
    );
    expect(button.onPressed, isNull);

    await _pump(
      tester,
      AsrLeftoverNotice(
        location: _location(),
        cleaning: false,
        onCleanUp: null,
      ),
    );
    button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('asr_leftover_clean_up')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('after a clean-up only the message stays', (tester) async {
    await _pump(
      tester,
      AsrLeftoverNotice(
        location: _location(const []),
        cleaning: false,
        message: '删除了 1 个重复文件夹',
        onCleanUp: () {},
      ),
    );

    expect(find.byKey(const ValueKey('asr_leftover_message')), findsOneWidget);
    expect(find.byKey(const ValueKey('asr_leftover_clean_up')), findsNothing);
    expect(find.text('重复的识别环境'), findsOneWidget);
  });

  group('confirmation', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmAsrLeftoverCleanup(context, _location()),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the dialog lists the leftovers and closes', (tester) async {
      await open(tester);
      expect(find.text(AsrLeftoverText.confirmTitle), findsOneWidget);
      expect(find.textContaining(_nested), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('asr_leftover_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(AsrLeftoverText.confirmTitle), findsNothing);
    });

    testWidgets('the answer reaches the caller', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await confirmAsrLeftoverCleanup(context, _location());
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AsrLeftoverText.confirmAction));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  });
}
