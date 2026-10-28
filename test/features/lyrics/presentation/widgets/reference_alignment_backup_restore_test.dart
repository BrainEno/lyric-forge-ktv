import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_restore_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_backup_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// 模拟编辑器接入方式：探测决定入口显隐，确认流程返回新文档后由宿主 setState。
class _RestoreHarness extends StatefulWidget {
  final LyricDocument initialDocument;

  const _RestoreHarness({required this.initialDocument});

  @override
  State<_RestoreHarness> createState() => _RestoreHarnessState();
}

class _RestoreHarnessState extends State<_RestoreHarness> {
  late LyricDocument document;
  bool hasChanges = false;

  @override
  void initState() {
    super.initState();
    document = widget.initialDocument;
  }

  Future<void> _restore(BuildContext context) async {
    final restored = await confirmReferenceAlignmentRestore(
      context,
      document: document,
    );
    if (restored == null || !mounted) return;
    setState(() {
      document = restored;
      hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final probe = const ReferenceAlignmentRestoreService().probeBackup(
      document,
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text(hasChanges ? 'state:dirty' : 'state:clean')),
        body: Builder(
          builder: (context) {
            final hasBackup = probe is ReferenceAlignmentBackupAvailable;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasBackup)
                  IconButton(
                    tooltip: '恢复对齐前版本',
                    onPressed: () => _restore(context),
                    icon: const Icon(Icons.history_rounded),
                  ),
                Text(
                  document.lines.isEmpty
                      ? '(empty)'
                      : document.lines.first.text,
                  key: const Key('document-text'),
                ),
                Text(
                  document.metadata.containsKey(kReferenceAlignmentRestoreKey)
                      ? 'restore-provenance:yes'
                      : 'restore-provenance:no',
                  key: const Key('restore-provenance'),
                ),
                Text(
                  document.metadata.containsKey(kReferenceAlignmentBackupKey)
                      ? 'backup:yes'
                      : 'backup:no',
                  key: const Key('backup-state'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

void main() {
  final backupDocument = LyricDocument(
    language: 'zh',
    lines: const [
      LyricLine(
        text: '月亮代表我的心',
        startTime: Duration(seconds: 1),
        endTime: Duration(seconds: 5),
      ),
      LyricLine(
        text: '今天天气真好',
        startTime: Duration(seconds: 5),
        endTime: Duration(seconds: 9),
      ),
    ],
  );

  Map<String, dynamic> validBackup() => <String, dynamic>{
    'createdAt': '2026-10-20T11:00:00.000',
    'reason': 'reference-alignment',
    'source': 'paste',
    'format': 'lrc',
    'timed': false,
    'referenceOffsetMs': 0,
    'lineCount': 2,
    'document': backupDocument.toJson(),
  };

  final editedDocument = LyricDocument(
    language: 'zh',
    lines: const [
      LyricLine(
        text: '月亮代表我的星（已改）',
        startTime: Duration(seconds: 1),
        endTime: Duration(seconds: 5),
      ),
    ],
    metadata: <String, dynamic>{kReferenceAlignmentBackupKey: validBackup()},
  );

  Future<void> pumpHarness(
    WidgetTester tester, {
    required LyricDocument document,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_RestoreHarness(initialDocument: document));
    await tester.pumpAndSettle();
  }

  testWidgets('无备份不显示恢复入口', (tester) async {
    const document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '只有草稿',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
      ],
    );

    await pumpHarness(tester, document: document);

    expect(find.byTooltip('恢复对齐前版本'), findsNothing);
    expect(find.byKey(const Key('document-text')), findsOneWidget);
  });

  testWidgets('损坏的备份不显示恢复入口', (tester) async {
    final broken = LyricDocument(
      language: 'zh',
      lines: const [
        LyricLine(
          text: '只有草稿',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
      ],
      metadata: <String, dynamic>{
        kReferenceAlignmentBackupKey: {...validBackup(), 'lineCount': 5},
      },
    );

    await pumpHarness(tester, document: broken);

    expect(find.byTooltip('恢复对齐前版本'), findsNothing);
  });

  testWidgets('有备份时入口可见，对话框展示备份摘要', (tester) async {
    await pumpHarness(tester, document: editedDocument);

    await tester.tap(find.byTooltip('恢复对齐前版本'));
    await tester.pumpAndSettle();

    expect(find.text('恢复对齐前版本'), findsOneWidget);
    expect(find.text('将覆盖当前编辑中的歌词，恢复后不会自动保存。'), findsOneWidget);
    expect(find.text('2026-10-20 11:00'), findsOneWidget);
    expect(find.text('粘贴（paste）'), findsOneWidget);
    expect(find.text('lrc'), findsOneWidget);
    expect(find.text('2 行'), findsOneWidget);
    expect(find.text('恢复并覆盖'), findsOneWidget);
  });

  testWidgets('取消恢复不修改文档', (tester) async {
    await pumpHarness(tester, document: editedDocument);

    await tester.tap(find.byTooltip('恢复对齐前版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('恢复对齐前版本'), findsNothing);
    expect(find.byKey(const Key('document-text')), findsOneWidget);
    expect(find.text('月亮代表我的星（已改）'), findsOneWidget);
    expect(find.text('state:clean'), findsOneWidget);
    expect(find.byKey(const Key('backup-state')), findsOneWidget);
    expect(find.text('backup:yes'), findsOneWidget);
    expect(find.text('restore-provenance:no'), findsOneWidget);
  });

  testWidgets('确认后备份文档被替换且备份键被消耗', (tester) async {
    await pumpHarness(tester, document: editedDocument);

    await tester.tap(find.byTooltip('恢复对齐前版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复并覆盖'));
    await tester.pumpAndSettle();

    expect(find.text('月亮代表我的心'), findsOneWidget);
    expect(find.text('月亮代表我的星（已改）'), findsNothing);
    expect(find.text('state:dirty'), findsOneWidget);
    expect(find.text('restore-provenance:yes'), findsOneWidget);
    expect(find.text('backup:no'), findsOneWidget);
    expect(find.byTooltip('恢复对齐前版本'), findsNothing);
  });
}
