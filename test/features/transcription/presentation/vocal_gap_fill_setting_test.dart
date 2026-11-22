import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/transcription_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/transcription_config_dialog.dart';

class _Profiles implements TranscriptionProfileResolver {
  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async => ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.custom,
    label: '自定义',
    description: 'test',
    hardware: const TranscriptionHardwareInfo(
      operatingSystem: 'windows',
      architecture: 'x86_64',
    ),
    config: config,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Checker implements AsrDownloadConnectionChecker {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Proxy implements TranscriptionDownloadProxyStore {
  final saved = <String>[];

  @override
  Future<String?> loadDownloadProxy() async => null;

  @override
  Future<void> saveDownloadProxy(String proxy) async => saved.add(proxy);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens the dialog from a button; [onResult] gets what it pops with.
Future<void> _open(
  WidgetTester tester,
  TranscriptionConfig initial, {
  ValueChanged<TranscriptionConfig?>? onResult,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showDialog<TranscriptionConfig>(
                context: context,
                builder: (_) => TranscriptionConfigDialog(
                  initialConfig: initial,
                  dependencies: TranscriptionConfigDialogDependencies(
                    profileResolver: _Profiles(),
                    downloadConnectionChecker: _Checker(),
                    downloadProxyStore: _Proxy(),
                  ),
                ),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  const initial = TranscriptionConfig(
    mode: TranscriptionMode.whisperOnly,
    whisperExecutable: 'whisper-cli',
    modelPath: 'ggml-large-v3.bin',
    downloadProxy: 'http://127.0.0.1:7890',
  );
  final toggle = find.byKey(const ValueKey('vocal_gap_fill_switch'));

  SwitchListTile tile(WidgetTester tester) =>
      tester.widget<SwitchListTile>(toggle);

  testWidgets('the switch shows the saved choice', (tester) async {
    await _open(
      tester,
      initial.copyWith(vocalGapFill: VocalGapFillPreference.off),
    );
    expect(find.text('识别后自动补全漏句'), findsOneWidget);
    expect(tile(tester).value, isFalse);
  });

  testWidgets('defaults to on and saves a change', (tester) async {
    TranscriptionConfig? result;
    await _open(tester, initial, onResult: (value) => result = value);

    expect(tile(tester).value, isTrue);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(tile(tester).value, isFalse);

    final button = find.text('保存并退出');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.vocalGapFill, VocalGapFillPreference.off);
    // Nothing else changed.
    expect(result!.vocalSeparation, initial.vocalSeparation);
    expect(result!.whisperExecutable, 'whisper-cli');
  });

  group('识别语言 (D-062)', () {
    final dropdown = find.byKey(
      const ValueKey('transcription_language_dropdown'),
    );

    String? shown(WidgetTester tester) => tester
        .widget<DropdownButtonFormField<String>>(dropdown)
        .initialValue;

    testWidgets('offers 自动判断 and the per-song languages', (tester) async {
      TranscriptionConfig? result;
      await _open(tester, initial, onResult: (value) => result = value);
      expect(shown(tester), 'auto');
      expect(find.text('自动判断'), findsOneWidget);

      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      for (final label in ['英文', '日文', '法语', '西班牙语', '俄语']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('法语').last);
      await tester.pumpAndSettle();

      final button = find.text('保存并退出');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(result?.language, 'fr');
    });

    testWidgets('an odd saved value still opens', (tester) async {
      await _open(tester, initial.copyWith(language: ' IT '));
      expect(shown(tester), 'it');
      expect(find.text('意大利语'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty saved value reads as 自动判断', (tester) async {
      await _open(tester, initial.copyWith(language: ''));
      expect(shown(tester), 'auto');
      expect(tester.takeException(), isNull);
    });
  });
}
