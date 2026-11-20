import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/timestamp_edit_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _line = LyricLine(
  text: '月亮代表我的心',
  startTime: Duration(seconds: 10),
  endTime: Duration(seconds: 14),
);

Duration _ms(int value) => Duration(milliseconds: value);

void main() {
  group('parse', () {
    test('minutes, seconds and hundredths', () {
      expect(LyricTimeInput.parse('01:23.45'), _ms(83450));
      expect(LyricTimeInput.parse('1:23.45'), _ms(83450));
    });

    test('a fraction is read as digits after the point', () {
      expect(LyricTimeInput.parse('00:01.5'), _ms(1500));
      expect(LyricTimeInput.parse('00:01.05'), _ms(1050));
      expect(LyricTimeInput.parse('00:01.123'), _ms(1123));
      expect(LyricTimeInput.parse('00:01.007'), _ms(1007));
    });

    test('a colon may separate the fraction', () {
      expect(LyricTimeInput.parse('02:03:40'), _ms(123400));
    });

    test('whole seconds and long recordings', () {
      expect(LyricTimeInput.parse('02:03'), _ms(123000));
      expect(LyricTimeInput.parse('120:00'), const Duration(hours: 2));
    });

    test('plain seconds', () {
      expect(LyricTimeInput.parse('83.5'), _ms(83500));
      expect(LyricTimeInput.parse('0'), Duration.zero);
      expect(LyricTimeInput.parse(' 7 '), _ms(7000));
    });

    test('nonsense is rejected', () {
      for (final input in [
        '',
        '   ',
        'abc',
        '01:60',
        '01:2a',
        '1:2:3:4',
        '-5',
        '00:01.1234',
        'NaN',
        'Infinity',
      ]) {
        expect(LyricTimeInput.parse(input), isNull, reason: input);
      }
    });
  });

  group('checks', () {
    test('a start must stay 10 ms before the end', () {
      expect(LyricTimeInput.rejection(_line, _ms(13990), start: true), isNull);
      expect(
        LyricTimeInput.rejection(_line, _ms(13991), start: true),
        '开始时间不能晚于结束时间',
      );
    });

    test('an end must stay 10 ms after the start', () {
      expect(LyricTimeInput.rejection(_line, _ms(10010), start: false), isNull);
      expect(
        LyricTimeInput.rejection(_line, _ms(10009), start: false),
        '结束时间不能早于开始时间',
      );
    });

    test('apply moves only the chosen end', () {
      final moved = LyricTimeInput.apply(_line, _ms(9000), start: true);
      expect(moved.startTime, _ms(9000));
      expect(moved.endTime, _line.endTime);
      expect(moved.text, _line.text);
      final later = LyricTimeInput.apply(_line, _ms(15000), start: false);
      expect(later.startTime, _line.startTime);
      expect(later.endTime, _ms(15000));
    });

    test('titles and labels name the end', () {
      expect(LyricTimeInput.title(start: true), '编辑开始时间');
      expect(LyricTimeInput.title(start: false), '编辑结束时间');
      expect(LyricTimeInput.label(start: true), '开始时间');
      expect(LyricTimeInput.label(start: false), '结束时间');
      expect(LyricTimeInput.current(_ms(83450)), '当前：01:23.45');
    });
  });

  group('dialog', () {
    Future<List<Duration?>> open(WidgetTester tester) async {
      final results = <Duration?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await showDialog<Duration>(
                    context: context,
                    builder: (_) => const TimestampEditDialog(
                      title: '编辑开始时间',
                      initial: Duration(seconds: 10),
                      label: '开始时间',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('starts with the current time', (tester) async {
      await open(tester);

      expect(find.text('编辑开始时间'), findsOneWidget);
      expect(find.text('00:10.00'), findsOneWidget);
      expect(find.text('当前：00:10.00'), findsOneWidget);
      expect(find.text('也支持 83.5（秒）'), findsOneWidget);
    });

    testWidgets('a bad time explains the format and stays open', (
      tester,
    ) async {
      final results = await open(tester);

      await tester.enterText(find.byType(TextField), '1:99');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text(LyricTimeInput.formatError), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('a good time pops with it', (tester) async {
      final results = await open(tester);

      await tester.enterText(find.byType(TextField), '00:12.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(results, [_ms(12500)]);
    });

    testWidgets('cancel pops with nothing', (tester) async {
      final results = await open(tester);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(results, [null]);
    });
  });

  group('editLyricLineTime', () {
    Future<List<LyricLine?>> open(WidgetTester tester, {required bool start}) async {
      final results = <LyricLine?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  results.add(
                    await editLyricLineTime(context, _line, start: start),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('returns the line with the new end', (tester) async {
      final results = await open(tester, start: false);
      expect(find.text('编辑结束时间'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '00:15');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(results.single?.endTime, _ms(15000));
      expect(results.single?.startTime, _line.startTime);
    });

    testWidgets('a start after the end is refused with a reason', (
      tester,
    ) async {
      final results = await open(tester, start: true);

      await tester.enterText(find.byType(TextField), '00:20');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(results, [null]);
      expect(find.text('开始时间不能晚于结束时间'), findsOneWidget);
    });

    testWidgets('cancelling changes nothing and says nothing', (tester) async {
      final results = await open(tester, start: true);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(results, [null]);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
