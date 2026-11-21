import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/ai_transcription_settings_cards.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/asr_runtime_overview.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_existing_model_actions.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_install_error_card.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_install_progress_card.dart';

const _config = TranscriptionConfig(
  whisperExecutable: 'whisper-cli',
  modelPath: '/models/ggml-large-v3.bin',
);

const _profile = ResolvedTranscriptionProfile(
  profile: TranscriptionProfilePreference.intelMacHighQuality,
  label: 'Intel Mac 高质量',
  description: '测试方案',
  hardware: TranscriptionHardwareInfo(
    operatingSystem: 'macos',
    architecture: 'x86_64',
  ),
  config: _config,
);

AsrRuntimeComponentStatus _component(
  AsrRuntimeComponent component,
  AsrRuntimeComponentState state,
) {
  return AsrRuntimeComponentStatus(
    component: component,
    state: state,
    label: AsrSettingsText.componentLabel(component),
    detail: '',
  );
}

AsrRuntimeStatus _status({required bool ready}) {
  return AsrRuntimeStatus(
    profile: _profile,
    managedRoot: '/runtime',
    components: [
      _component(AsrRuntimeComponent.ffmpeg, AsrRuntimeComponentState.ready),
      _component(
        AsrRuntimeComponent.whisperModel,
        ready
            ? AsrRuntimeComponentState.ready
            : AsrRuntimeComponentState.missing,
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
}

ButtonStyleButton _buttonWithText(WidgetTester tester, String label) {
  return tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ),
  );
}

AsrMaintenanceCard _maintenance({
  bool ready = false,
  bool loading = false,
  bool busy = false,
  bool storageBlocked = false,
  bool installing = false,
  bool paused = false,
  AsrRuntimeInstallProgress? progress,
  String? error,
  AsrRuntimeComponent? failedComponent,
  List<String>? log,
}) {
  final calls = log ?? <String>[];
  return AsrMaintenanceCard(
    ready: ready,
    loading: loading,
    busy: busy,
    storageBlocked: storageBlocked,
    installing: installing,
    paused: paused,
    progress: progress,
    error: error,
    failedComponent: failedComponent,
    onRefresh: () => calls.add('refresh'),
    onInstall: () => calls.add('install'),
    onPause: () => calls.add('pause'),
    onResume: () => calls.add('resume'),
    onRetry: () => calls.add('retry'),
    onDelete: (reinstall) => calls.add('delete $reinstall'),
  );
}

void main() {
  group('AsrSettingsText', () {
    test('basename handles both separators', () {
      expect(AsrSettingsText.basename('/a/b/model.bin'), 'model.bin');
      expect(AsrSettingsText.basename(r'C:\models\ggml.bin'), 'ggml.bin');
      expect(AsrSettingsText.basename('/'), '/');
    });

    test('bytes read as MB below a gigabyte and GB above', () {
      expect(AsrSettingsText.formatBytes(null), '无法读取');
      expect(AsrSettingsText.formatBytes(0), '0 MB');
      expect(AsrSettingsText.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(AsrSettingsText.formatBytes(300 * 1024 * 1024), '300 MB');
      expect(AsrSettingsText.formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
      expect(AsrSettingsText.formatBytes(12 * 1024 * 1024 * 1024), '12.0 GB');
    });

    test('the model summary names what a run will use', () {
      expect(
        AsrSettingsText.modelSummary(_config),
        'Qwen3-ASR 1.7B + ForcedAligner 0.6B + ggml-large-v3.bin fallback',
      );
      expect(
        AsrSettingsText.modelSummary(
          const TranscriptionConfig(
            mode: TranscriptionMode.whisperOnly,
            whisperExecutable: 'whisper-cli',
            modelPath: '',
          ),
        ),
        'Whisper large-v3（待安装） · Whisper runtime',
      );
    });

    test('install state reads ready, installing, unknown or a count', () {
      String state(AsrRuntimeStatus? status, {bool installing = false}) {
        return AsrSettingsText.installState(
          status: status,
          installing: installing,
        );
      }

      expect(state(_status(ready: true)), '已就绪');
      expect(state(_status(ready: false), installing: true), '正在安装');
      expect(state(null), '未检测');
      expect(state(_status(ready: false)), '1/2 个组件已就绪');
    });

    test('the install button says what it will do', () {
      String action({
        bool ready = false,
        bool blocked = false,
        bool failed = false,
        AsrRuntimeComponent? component,
      }) {
        return AsrSettingsText.installAction(
          ready: ready,
          storageBlocked: blocked,
          failed: failed,
          failedComponent: component,
        );
      }

      expect(action(blocked: true, failed: true), '空间不足');
      expect(action(failed: true), AsrSettingsText.retryUnfinished);
      expect(
        action(failed: true, component: AsrRuntimeComponent.qwenModel),
        '重试 Qwen 模型',
      );
      expect(action(ready: true), '校验并修复');
      expect(action(), '校验并补齐缺失组件');
    });

    test('moving storage shows bytes once the total is known', () {
      expect(AsrSettingsText.movingStorage(0, 0), '正在迁移识别环境…');
      expect(
        AsrSettingsText.movingStorage(1024 * 1024, 10 * 1024 * 1024),
        '正在迁移 1.0 MB / 10 MB',
      );
    });

    test('configured paths mark empty values as unset', () {
      final rows = AsrSettingsText.configuredPaths(_config);
      expect(rows.map((row) => row.$1), [
        'Qwen runtime',
        'Qwen 模型',
        'ForcedAligner',
        'Whisper runtime',
        'Whisper 模型',
        'FFmpeg',
      ]);
      expect(rows.first.$2, '未指定');
      expect(rows[4].$2, '/models/ggml-large-v3.bin');
    });
  });

  group('AsrPlanCard', () {
    testWidgets('shows the profile, the ready state in green and components', (
      tester,
    ) async {
      await _pump(
        tester,
        AsrPlanCard(
          config: _config,
          status: _status(ready: true),
          loading: false,
          installing: false,
          managedBytes: 2 * 1024 * 1024 * 1024,
          onModeChanged: (_) {},
        ),
      );

      expect(find.text('Intel Mac 高质量'), findsOneWidget);
      expect(find.text('2.00 GB'), findsOneWidget);
      final state = tester.widget<AsrInfoTile>(
        find.widgetWithText(AsrInfoTile, '安装状态'),
      );
      expect(state.value, '已就绪');
      expect(state.valueColor, AppColors.success);
      expect(find.byType(AsrComponentList), findsOneWidget);
    });

    testWidgets('before detection there is no component list', (tester) async {
      await _pump(
        tester,
        const AsrPlanCard(
          config: _config,
          status: null,
          loading: true,
          installing: false,
          managedBytes: null,
          onModeChanged: null,
        ),
      );

      expect(find.text('正在检测…'), findsOneWidget);
      expect(find.byType(AsrComponentList), findsNothing);
    });

    testWidgets('choosing another plan reports it once', (tester) async {
      final chosen = <TranscriptionMode>[];
      await _pump(
        tester,
        AsrPlanCard(
          config: _config,
          status: null,
          loading: false,
          installing: false,
          managedBytes: null,
          onModeChanged: chosen.add,
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<TranscriptionMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whisper 单模型 · 更省空间').last);
      await tester.pumpAndSettle();
      expect(chosen, [TranscriptionMode.whisperOnly]);
    });
  });

  group('AsrStorageSettingsCard', () {
    AsrStorageSettingsCard card({
      bool ready = false,
      String? message,
      bool moving = false,
      bool isDefault = true,
    }) {
      return AsrStorageSettingsCard(
        ready: ready,
        loading: false,
        storage: null,
        location: AsrManagedStorageLocation(
          activeRoot: '/runtime',
          defaultRoot: '/default',
          managedBytes: 0,
          isDefault: isDefault,
        ),
        scanningExisting: false,
        existingModelMessage: message,
        movingStorage: moving,
        movingCopiedBytes: 1024 * 1024,
        movingTotalBytes: 4 * 1024 * 1024,
        onScan: () {},
        onPastePath: () {},
        onBrowse: () {},
        onChangeLocation: () {},
        onRestoreDefault: () {},
      );
    }

    testWidgets('offers existing models until the runtime is ready', (
      tester,
    ) async {
      await _pump(tester, card());
      expect(find.byType(AsrExistingModelCard), findsOneWidget);

      await _pump(tester, card(ready: true));
      expect(find.byType(AsrExistingModelCard), findsNothing);

      await _pump(tester, card(ready: true, message: '已识别 2 个模型'));
      expect(find.byType(AsrExistingModelCard), findsOneWidget);
    });

    testWidgets('leftover copies are listed with a clean-up button (D-048)', (
      tester,
    ) async {
      var cleaned = 0;
      Widget withLeftovers() {
        return AsrStorageSettingsCard(
          ready: true,
          loading: false,
          storage: null,
          location: const AsrManagedStorageLocation(
            activeRoot: '/runtime',
            defaultRoot: '/default',
            managedBytes: 0,
            isDefault: false,
            leftovers: [
              AsrRuntimeLeftover(
                path: '/runtime/LyricForge/ASRRuntime',
                kind: AsrRuntimeLeftoverKind.nestedCopy,
                bytes: 1 << 30,
                files: 3,
              ),
            ],
          ),
          scanningExisting: false,
          existingModelMessage: null,
          movingStorage: false,
          movingCopiedBytes: 0,
          movingTotalBytes: 0,
          onCleanUpLeftovers: () => cleaned++,
          onScan: () {},
          onPastePath: () {},
          onBrowse: () {},
          onChangeLocation: () {},
          onRestoreDefault: () {},
        );
      }

      await _pump(tester, card(ready: true));
      expect(find.byType(AsrLeftoverNotice), findsNothing);

      await _pump(tester, withLeftovers());
      expect(find.byType(AsrLeftoverNotice), findsOneWidget);
      expect(find.textContaining('/runtime/LyricForge/ASRRuntime'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('asr_leftover_clean_up')));
      expect(cleaned, 1);
    });

    testWidgets('restoring the default appears only after a move', (
      tester,
    ) async {
      await _pump(tester, card());
      expect(find.text('迁回默认位置'), findsNothing);

      await _pump(tester, card(isDefault: false, moving: true));
      expect(find.text('迁回默认位置'), findsOneWidget);
      expect(find.text('正在迁移 1.0 MB / 4.0 MB'), findsOneWidget);
    });
  });

  group('AsrMaintenanceCard', () {
    testWidgets('idle: install, refresh and delete run their actions', (
      tester,
    ) async {
      final log = <String>[];
      await _pump(tester, _maintenance(log: log));

      await tester.tap(find.text('校验并补齐缺失组件'));
      await tester.tap(find.text('重新检测'));
      await tester.tap(find.text('删除模型'));
      await tester.tap(find.text('删除并重装模型'));
      expect(log, ['install', 'refresh', 'delete false', 'delete true']);
    });

    testWidgets('busy disables everything but the install button', (
      tester,
    ) async {
      await _pump(tester, _maintenance(busy: true));

      expect(_buttonWithText(tester, '重新检测').onPressed, isNull);
      expect(_buttonWithText(tester, '删除模型').onPressed, isNull);
      expect(_buttonWithText(tester, '删除并重装模型').onPressed, isNull);
    });

    testWidgets('not enough space blocks the install', (tester) async {
      await _pump(tester, _maintenance(storageBlocked: true));

      expect(_buttonWithText(tester, '空间不足').onPressed, isNull);
    });

    testWidgets('a running download can be paused', (tester) async {
      final log = <String>[];
      await _pump(
        tester,
        _maintenance(
          installing: true,
          busy: true,
          progress: const AsrRuntimeInstallProgress(
            progress: 0.4,
            message: '下载中',
          ),
          log: log,
        ),
      );

      expect(find.byType(AsrInstallProgressCard), findsOneWidget);
      // The progress card and the action row both offer it.
      expect(find.text('暂停下载'), findsNWidgets(2));
      await tester.tap(find.text('暂停下载').last);
      expect(log, ['pause']);
    });

    testWidgets('a paused download can be continued', (tester) async {
      final log = <String>[];
      await _pump(
        tester,
        _maintenance(
          paused: true,
          busy: true,
          progress: const AsrRuntimeInstallProgress(
            progress: 0.4,
            message: '已暂停',
          ),
          log: log,
        ),
      );

      expect(find.text('继续下载'), findsNWidgets(2));
      await tester.tap(find.text('继续下载').last);
      expect(log, ['resume']);
    });

    testWidgets('a failure shows the error and names the component', (
      tester,
    ) async {
      final log = <String>[];
      await _pump(
        tester,
        _maintenance(
          error: '下载失败',
          failedComponent: AsrRuntimeComponent.whisperModel,
          log: log,
        ),
      );

      expect(find.byType(AsrInstallErrorCard), findsOneWidget);
      await tester.tap(find.text('重试 Whisper 模型'));
      expect(log, ['install']);
    });
  });

  group('AsrAdvancedSettingsCard', () {
    testWidgets('lists each path under its own label', (tester) async {
      var opened = 0;
      await _pump(
        tester,
        AsrAdvancedSettingsCard(
          config: _config,
          onOpenAdvanced: () => opened++,
        ),
      );

      await tester.tap(find.text('查看当前路径'));
      await tester.pumpAndSettle();
      expect(find.text('Whisper 模型'), findsOneWidget);
      expect(find.text('/models/ggml-large-v3.bin'), findsOneWidget);
      expect(find.text('ffmpeg'), findsOneWidget);

      await tester.tap(find.text('手工选择模型路径和 runtime'));
      expect(opened, 1);
    });

    testWidgets('the editor is disabled while busy', (tester) async {
      await _pump(
        tester,
        const AsrAdvancedSettingsCard(config: _config, onOpenAdvanced: null),
      );

      expect(_buttonWithText(tester, '手工选择模型路径和 runtime').onPressed, isNull);
    });
  });
}
