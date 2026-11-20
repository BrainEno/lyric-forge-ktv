import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_runtime_setup_cards.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_runtime_setup_controller.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart';

import 'asr_setup_fakes.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

/// Opens the dialog from a button and records what it popped with.
class _Launcher extends StatefulWidget {
  const _Launcher({required this.runtime, this.preflight});

  final FakeSetupRuntime runtime;
  final FakeSetupPreflight? preflight;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  final results = <TranscriptionConfig?>[];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () async {
          final result = await showDialog<TranscriptionConfig>(
            context: context,
            builder: (_) => AsrRuntimeSetupDialog(
              dependencies: setupDependencies(
                runtime: widget.runtime,
                preflight: widget.preflight,
              ),
            ),
          );
          results.add(result);
        },
        child: const Text('open'),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<_LauncherState> _open(
  WidgetTester tester,
  FakeSetupRuntime runtime, {
  FakeSetupPreflight? preflight,
  Size size = const Size(1366, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: _Launcher(runtime: runtime, preflight: preflight),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  return tester.state<_LauncherState>(find.byType(_Launcher));
}

void main() {
  group('cards', () {
    testWidgets('the header is a heading and follows readiness', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const AsrSetupHeader(ready: false, installing: true)),
      );

      expect(find.text('正在准备本地歌词识别'), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      final title = tester.getSemantics(find.text('正在准备本地歌词识别'));
      expect(title, isSemantics(isHeader: true));
      expect(title.label, contains('正在准备本地歌词识别'));

      await tester.pumpWidget(
        _host(const AsrSetupHeader(ready: true, installing: false)),
      );
      expect(find.text('本地歌词识别已准备好'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a step is read as one heading with its number', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const AsrSetupStep(number: 2, title: '检查这台电脑', subtitle: '说明')),
      );

      final node = tester.getSemantics(find.byType(AsrSetupStep));
      expect(node.label, contains('第 2 步'));
      expect(node.label, contains('检查这台电脑'));
      expect(node.label, contains('说明'));
      expect(node, isSemantics(isHeader: true));
      semantics.dispose();
    });

    testWidgets('the mode field reports a new mode', (tester) async {
      TranscriptionMode? picked;
      await tester.pumpWidget(
        _host(
          AsrSetupModeField(
            mode: TranscriptionMode.highestQuality,
            onChanged: (mode) => picked = mode,
          ),
        ),
      );

      await tester.tap(find.text('最高质量 · 双引擎校对（推荐）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whisper 单模型 · 更省空间').last);
      await tester.pumpAndSettle();

      expect(picked, TranscriptionMode.whisperOnly);
    });

    testWidgets('the mode field can be locked', (tester) async {
      await tester.pumpWidget(
        _host(
          const AsrSetupModeField(
            mode: TranscriptionMode.whisperOnly,
            onChanged: null,
          ),
        ),
      );

      final field = tester.widget<DropdownButtonFormField<TranscriptionMode>>(
        find.byType(DropdownButtonFormField<TranscriptionMode>),
      );
      expect(field.onChanged, isNull);
      expect(find.text('Whisper 单模型 · 更省空间'), findsOneWidget);
    });

    testWidgets('the profile card shows the matched hardware', (tester) async {
      await tester.pumpWidget(
        _host(AsrSetupProfileCard.fromStatus(setupStatus(ready: false))),
      );

      expect(find.text('Apple 芯片高质量'), findsOneWidget);
      expect(find.text('测试方案'), findsOneWidget);
      expect(find.text('macos / arm64 · Apple M2 · 16 GB RAM'), findsOneWidget);
      expect(find.text('自动推荐'), findsOneWidget);
      expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
    });

    testWidgets('a ready profile says so', (tester) async {
      await tester.pumpWidget(
        _host(AsrSetupProfileCard.fromStatus(setupStatus(ready: true))),
      );

      expect(find.text('已就绪'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('the components card lists each with a divider between', (
      tester,
    ) async {
      final status = setupStatus(ready: false);
      await tester.pumpWidget(
        _host(
          AsrSetupComponentsCard(components: status.components, ready: false),
        ),
      );

      expect(find.text('首次使用需要准备'), findsOneWidget);
      expect(find.byType(AsrSetupComponentRow), findsNWidgets(2));
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('已准备'), findsOneWidget);
      expect(find.text('待准备'), findsOneWidget);
    });

    testWidgets('a component row is read as one sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      final component = setupStatus(ready: true).components.first;
      await tester.pumpWidget(
        _host(AsrSetupComponentRow(component: component)),
      );

      expect(
        tester.getSemantics(find.byType(AsrSetupComponentRow)),
        isSemantics(label: 'FFmpeg，已准备，系统已安装'),
      );
      semantics.dispose();
    });

    test('a row without a detail leaves it out', () {
      const component = AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.qwenModel,
        state: AsrRuntimeComponentState.unavailable,
        label: 'Qwen 模型',
        detail: ' ',
      );
      expect(AsrSetupComponentRow.semanticLabel(component), 'Qwen 模型，需手动配置');
    });

    test('each state has its icon', () {
      expect(
        AsrSetupComponentRow.styleFor(AsrRuntimeComponentState.ready).$1,
        Icons.check_circle_rounded,
      );
      expect(
        AsrSetupComponentRow.styleFor(AsrRuntimeComponentState.unavailable).$1,
        Icons.tune_rounded,
      );
      expect(
        AsrSetupComponentRow.styleFor(AsrRuntimeComponentState.failed).$1,
        Icons.radio_button_unchecked_rounded,
      );
    });

    testWidgets('the hint reassures about folders', (tester) async {
      await tester.pumpWidget(_host(const AsrSetupHint()));

      expect(find.textContaining('不需要理解模型目录层级'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    test('resume, install and start are the filled buttons', () {
      expect(
        [
          for (final action in AsrSetupAction.values)
            if (AsrSetupActionButton.isPrimary(action)) action,
        ],
        [AsrSetupAction.resume, AsrSetupAction.install, AsrSetupAction.start],
      );
    });

    testWidgets('every action has its label', (tester) async {
      const labels = {
        AsrSetupAction.pause: '暂停下载',
        AsrSetupAction.later: '以后继续',
        AsrSetupAction.resume: '继续下载',
        AsrSetupAction.advanced: '高级设置',
        AsrSetupAction.refresh: '重新检测',
        AsrSetupAction.install: '校验并准备识别环境',
        AsrSetupAction.start: '开始使用',
      };
      for (final entry in labels.entries) {
        await tester.pumpWidget(
          _host(AsrSetupActionButton(action: entry.key, onPressed: () {})),
        );
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      }
    });

    testWidgets('a blocked install says 空间不足 and is disabled', (tester) async {
      await tester.pumpWidget(
        _host(
          const AsrSetupActionButton(
            action: AsrSetupAction.install,
            onPressed: null,
            storageBlocked: true,
          ),
        ),
      );

      expect(find.text('空间不足'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('dialog', () {
    testWidgets('shows the plan, this computer and the first-run actions', (
      tester,
    ) async {
      final runtime = FakeSetupRuntime();
      await _open(tester, runtime);

      expect(find.text('首次使用，只需完成一次准备'), findsOneWidget);
      expect(find.text('选择识别方案'), findsOneWidget);
      expect(find.text('检查这台电脑'), findsOneWidget);
      expect(find.text('Apple 芯片高质量'), findsOneWidget);
      expect(find.byType(AsrSetupComponentRow), findsNWidgets(2));
      expect(find.text('一键识别已有模型'), findsOneWidget);
      expect(find.text('高级设置'), findsOneWidget);
      expect(find.text('重新检测'), findsOneWidget);
      expect(find.text('校验并准备识别环境'), findsOneWidget);
      expect(find.text('开始使用'), findsNothing);
      expect(tester.takeException(), isNull);
      await runtime.progress.close();
    });

    testWidgets('installs, then pops with the ready plan', (tester) async {
      final runtime = FakeSetupRuntime()
        ..statusAfterInstall = setupStatus(ready: true);
      final launcher = await _open(tester, runtime);

      await tester.tap(find.text('校验并准备识别环境'));
      await _settle(tester);

      expect(runtime.installCalls, 1);
      expect(find.text('本地歌词识别已准备好'), findsOneWidget);
      await tester.tap(find.text('开始使用'));
      await _settle(tester);

      expect(launcher.results.single?.modelPath, '/runtime/models/ggml.bin');
      expect(find.byType(AsrRuntimeSetupDialog), findsNothing);
      await runtime.progress.close();
    });

    testWidgets('a full disk disables the install button', (tester) async {
      final runtime = FakeSetupRuntime();
      final preflight = FakeSetupPreflight()
        ..state = AsrStoragePreflightState.insufficient;
      await _open(tester, runtime, preflight: preflight);

      expect(find.text('空间不足'), findsOneWidget);
      expect(find.text('校验并准备识别环境'), findsNothing);
      await tester.tap(find.text('空间不足'));
      await _settle(tester);
      expect(runtime.installCalls, 0);
      await runtime.progress.close();
    });

    testWidgets('a download can be paused, and then left or continued', (
      tester,
    ) async {
      final runtime = FakeSetupRuntime()
        ..pendingInstall = Completer<TranscriptionConfig>();
      final launcher = await _open(tester, runtime);

      await tester.tap(find.text('校验并准备识别环境'));
      await _settle(tester);
      expect(find.text('正在准备本地歌词识别'), findsOneWidget);
      expect(find.text('暂停下载'), findsWidgets);
      expect(find.text('高级设置'), findsNothing);

      // Back does not close the dialog while downloading.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await _settle(tester);
      expect(find.byType(AsrRuntimeSetupDialog), findsOneWidget);

      await tester.tap(find.text('暂停下载').last);
      await _settle(tester);
      expect(runtime.cancelCalls, 1);
      expect(find.text('以后继续'), findsOneWidget);
      expect(find.text('继续下载'), findsWidgets);

      await tester.tap(find.text('以后继续'));
      await _settle(tester);
      expect(find.byType(AsrRuntimeSetupDialog), findsNothing);
      expect(launcher.results.single, isNull);
      await runtime.progress.close();
    });

    testWidgets('changing the mode inspects the new plan', (tester) async {
      final runtime = FakeSetupRuntime();
      await _open(tester, runtime);

      await tester.tap(find.text('最高质量 · 双引擎校对（推荐）'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Whisper 单模型 · 更省空间').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);

      expect(runtime.inspected.last.mode, TranscriptionMode.whisperOnly);
      await runtime.progress.close();
    });

    testWidgets('a failed install names the component to retry', (
      tester,
    ) async {
      final runtime = FakeSetupRuntime()
        ..pendingInstall = Completer<TranscriptionConfig>();
      await _open(tester, runtime);
      await tester.tap(find.text('校验并准备识别环境'));
      await _settle(tester);
      runtime.progress.add(
        const AsrRuntimeInstallProgress(
          component: AsrRuntimeComponent.whisperModel,
          progress: 0.3,
          message: '正在下载 Whisper 模型',
          phase: AsrRuntimeInstallPhase.downloading,
        ),
      );
      await _settle(tester);

      runtime.pendingInstall!.completeError(
        const TranscriptionException.environment('网络中断'),
      );
      await _settle(tester);

      expect(find.text('重试 Whisper 模型'), findsOneWidget);
      expect(find.textContaining('网络中断'), findsWidgets);
      expect(find.text('高级设置'), findsOneWidget);
      await runtime.progress.close();
    });

    testWidgets('fits a phone without overflow', (tester) async {
      final runtime = FakeSetupRuntime();
      await _open(tester, runtime, size: const Size(390, 844));

      expect(find.byType(AsrRuntimeSetupDialog), findsOneWidget);
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
      await runtime.progress.close();
    });
  });
}
