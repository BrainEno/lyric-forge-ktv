import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_existing_model_actions.dart';

void main() {
  group('AsrFolderText on Windows', () {
    test('names the folder the way Explorer shows it', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AsrFolderText.separator, r'\');
      expect(AsrFolderText.folder, r'LyricForge\ASRRuntime');
      expect(AsrFolderText.exampleParent, r'D:\Models');
      expect(AsrFolderText.example, r'D:\Models\LyricForge\ASRRuntime');
      debugDefaultTargetPlatformOverride = null;
    });

    test('offers a drive, a parent and the folder as hints', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final hint = AsrFolderText.pasteHint;
      expect(hint, startsWith('例如 D:\\、'));
      expect(hint, contains(r'D:\Models 或'));
      expect(hint, endsWith(r'D:\Models\LyricForge\ASRRuntime'));
      debugDefaultTargetPlatformOverride = null;
    });

    test('every message spells the folder as a path', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final messages = <String>[
        AsrFolderText.pasteExplanation,
        AsrFolderText.cardMessage,
        AsrFolderText.scanningFallback,
        AsrFolderText.pickExistingTitle,
        AsrFolderText.pickNewParentTitle,
        AsrFolderText.scanning,
        AsrFolderText.notFound,
        AsrFolderText.checkingPath(r'E:\'),
        AsrFolderText.pathNotRecognised,
        AsrFolderText.moveConfirmation('3.2 GB'),
      ];
      for (final message in messages) {
        expect(message, contains(r'LyricForge\ASRRuntime'), reason: message);
        expect(message, isNot(contains('LyricForge ASRRuntime')));
        expect(message, isNot(contains('LyricForge/ASRRuntime')));
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('the long messages show the full example path', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      const example = r'D:\Models\LyricForge\ASRRuntime';
      expect(AsrFolderText.pasteExplanation, contains(example));
      expect(AsrFolderText.cardMessage, contains(example));
      expect(AsrFolderText.notFound, contains(example));
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('AsrFolderText on other platforms', () {
    test('macOS uses forward slashes and a volume example', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(AsrFolderText.separator, '/');
      expect(AsrFolderText.folder, 'LyricForge/ASRRuntime');
      expect(
        AsrFolderText.example,
        '/Volumes/Data/Models/LyricForge/ASRRuntime',
      );
      expect(AsrFolderText.pasteHint, isNot(contains(r'\')));
      expect(AsrFolderText.pasteHint, isNot(contains('D:')));
      debugDefaultTargetPlatformOverride = null;
    });

    test('Linux uses a mount example', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(AsrFolderText.example, '/mnt/data/Models/LyricForge/ASRRuntime');
      expect(
        AsrFolderText.pasteHint,
        '例如 /mnt/data/Models 或 /mnt/data/Models/LyricForge/ASRRuntime',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    test('no message leaks a Windows path off Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final messages = <String>[
        AsrFolderText.pasteExplanation,
        AsrFolderText.cardMessage,
        AsrFolderText.notFound,
        AsrFolderText.moveConfirmation('1 GB'),
      ];
      for (final message in messages) {
        expect(message, contains('LyricForge/ASRRuntime'));
        expect(message, isNot(contains(r'\')), reason: message);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('AsrFolderText messages', () {
    test('the reuse flow keeps promising not to download', () {
      expect(AsrFolderText.scanning, endsWith('此步骤不会下载。'));
      expect(AsrFolderText.checkingPath('/x'), endsWith('此步骤不会下载。'));
      expect(AsrFolderText.scanningFallback, contains('不会下载'));
      expect(AsrFolderText.cardMessage, contains('不会开始下载'));
    });

    test('checkingPath quotes the path the user chose', () {
      expect(
        AsrFolderText.checkingPath('/srv/models'),
        startsWith('正在从 /srv/models 识别'),
      );
    });

    test('a failed path says the current folder is unchanged', () {
      expect(AsrFolderText.pathNotRecognised, endsWith('当前目录未改变。'));
    });

    test('the move confirmation carries the size and the copy-first rule', () {
      final text = AsrFolderText.moveConfirmation('812 MB');
      expect(text, startsWith('当前托管环境约 812 MB。'));
      expect(text, contains('不复制、不删除当前目录'));
      expect(text, contains('确认新目录完整后才切换路径'));
      expect(text, endsWith('操作期间不会启动识别任务。'));
    });

    test('labels no longer use the bare runtime name', () {
      expect(AsrFolderText.browseLabel, '浏览模型文件夹');
      expect(AsrFolderText.pasteTitle, '粘贴已有模型文件夹的路径');
      expect(AsrFolderText.browseLabel, isNot(contains('ASRRuntime')));
      expect(AsrFolderText.pasteTitle, isNot(contains('ASRRuntime')));
    });
  });

  group('AsrExistingModelCard', () {
    Widget host(Widget child) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 720, child: child),
          ),
        ),
      );
    }

    testWidgets('shows the folder path and the example on Windows', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(
        host(
          AsrExistingModelCard(
            scanning: false,
            onScan: () {},
            onPastePath: () {},
            onBrowse: () {},
          ),
        ),
      );

      expect(
        find.textContaining(r'D:\Models\LyricForge\ASRRuntime'),
        findsOneWidget,
      );
      expect(find.textContaining('LyricForge ASRRuntime'), findsNothing);
      expect(find.text('浏览模型文件夹'), findsOneWidget);
      expect(find.text('一键识别已有模型'), findsOneWidget);
      expect(find.text('粘贴路径识别'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('names the folder while scanning without a message', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(
        host(
          AsrExistingModelCard(
            scanning: true,
            onScan: () {},
            onPastePath: () {},
            onBrowse: () {},
          ),
        ),
      );

      expect(
        find.text(r'正在查找已有的 LyricForge\ASRRuntime 文件夹…（不会下载）'),
        findsOneWidget,
      );
      expect(find.text('正在识别已有模型…'), findsOneWidget);
      final browse = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('浏览模型文件夹'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      );
      expect(browse.onPressed, isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a message of the flow replaces the fallback', (tester) async {
      await tester.pumpWidget(
        host(
          AsrExistingModelCard(
            scanning: false,
            message: '已找到已有环境：/mnt/data/Models/LyricForge/ASRRuntime。',
            onScan: () {},
            onPastePath: () {},
            onBrowse: () {},
          ),
        ),
      );

      expect(find.textContaining('已找到已有环境'), findsOneWidget);
      expect(find.textContaining('（不会下载）'), findsNothing);
    });

    testWidgets('the browse button calls back', (tester) async {
      var browsed = 0;
      await tester.pumpWidget(
        host(
          AsrExistingModelCard(
            scanning: false,
            onScan: () {},
            onPastePath: () {},
            onBrowse: () => browsed++,
          ),
        ),
      );

      await tester.tap(find.text('浏览模型文件夹'));
      await tester.pump();
      expect(browsed, 1);
    });
  });

  group('showAsrExistingModelPathDialog', () {
    Future<void> open(
      WidgetTester tester,
      void Function(String?) onDone,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    onDone(await showAsrExistingModelPathDialog(context));
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('explains the folder with the Windows example', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await open(tester, (_) {});

      expect(find.text('粘贴已有模型文件夹的路径'), findsOneWidget);
      expect(
        find.textContaining(r'模型放在 LyricForge\ASRRuntime 文件夹里'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.decoration?.hintText,
        r'例如 D:\、D:\Models 或 D:\Models\LyricForge\ASRRuntime',
      );
      expect(field.decoration?.labelText, '已有模型路径');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('returns the pasted path trimmed', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      String? result;
      await open(tester, (value) => result = value);

      final submit = find.ancestor(
        of: find.text('识别并使用'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byType(TextField),
        '  D:\\Models\\LyricForge\\ASRRuntime  ',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

      await tester.tap(find.text('识别并使用'));
      await tester.pumpAndSettle();
      expect(result, r'D:\Models\LyricForge\ASRRuntime');
      expect(find.byType(AlertDialog), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('cancel returns nothing', (tester) async {
      var closed = false;
      String? result = 'unset';
      await open(tester, (value) {
        closed = true;
        result = value;
      });

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });
}
