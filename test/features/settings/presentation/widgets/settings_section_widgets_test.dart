import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_badge.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/asr_runtime_overview.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/settings_section_card.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('section cards show a header, explanation and content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SettingsSectionCard(
          icon: Icons.folder_rounded,
          title: '模型与存储',
          subtitle: '识别本机已有的模型。',
          child: Text('内容'),
        ),
      ),
    );

    expect(find.text('模型与存储'), findsOneWidget);
    expect(find.text('识别本机已有的模型。'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    final header = find.ancestor(
      of: find.text('模型与存储'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      ),
    );
    expect(header, findsOneWidget);
  });

  test('info grid uses one, two or three columns by width', () {
    expect(AsrInfoGrid.columnsFor(390), 1);
    expect(AsrInfoGrid.columnsFor(639), 1);
    expect(AsrInfoGrid.columnsFor(640), 2);
    expect(AsrInfoGrid.columnsFor(979), 2);
    expect(AsrInfoGrid.columnsFor(980), 3);
  });

  testWidgets('info tiles share the row width evenly', (tester) async {
    // The scroll view gives the grid the full surface width.
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        const AsrInfoGrid(
          children: [
            AsrInfoTile(label: '当前推荐方案', value: '最高质量'),
            AsrInfoTile(label: '安装状态', value: '已就绪'),
            AsrInfoTile(label: '安装目录', value: '/models', selectable: true),
          ],
        ),
      ),
    );

    final first = tester.getRect(find.byType(AsrInfoTile).at(0));
    final third = tester.getRect(find.byType(AsrInfoTile).at(2));
    expect(first.top, third.top, reason: 'three tiles fit on one row');
    expect(first.width, closeTo((1000 - 2 * 8) / 3, 0.01));
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('component rows show Chinese state badges', (tester) async {
    await tester.pumpWidget(
      _host(
        const AsrComponentList(
          components: [
            AsrRuntimeComponentStatus(
              component: AsrRuntimeComponent.ffmpeg,
              state: AsrRuntimeComponentState.ready,
              label: 'FFmpeg',
              detail: '/usr/bin/ffmpeg',
            ),
            AsrRuntimeComponentStatus(
              component: AsrRuntimeComponent.whisperModel,
              state: AsrRuntimeComponentState.missing,
              label: 'Whisper 模型',
              detail: '尚未下载',
            ),
          ],
        ),
      ),
    );

    expect(find.text('已安装'), findsOneWidget);
    expect(find.text('未安装'), findsOneWidget);
    expect(find.text('missing'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
  });

  test('every component state has a label and a tone', () {
    for (final state in AsrRuntimeComponentState.values) {
      expect(AsrComponentList.stateLabel(state), isNotEmpty);
      expect(AsrComponentList.stateTone(state), isA<AppBadgeTone>());
    }
    expect(
      AsrComponentList.stateTone(AsrRuntimeComponentState.failed),
      AppBadgeTone.error,
    );
  });
}
