import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_backing_mode.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_entry_sheet.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/automatic_accompaniment.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets('missing instrumental shows realistic guidance at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      KtvEntrySelection? selection;
      await tester.pumpWidget(
        _SheetHost(
          asset: const AudioAsset(originalPath: 'song.wav', format: 'wav'),
          onSelected: (mode) => selection = mode,
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text(ktvInstrumentalUnavailableHint), findsOneWidget);
      expect(ktvInstrumentalUnavailableHint, contains('自动生成伴奏'));
      final instrumental = tester.widget<ListTile>(
        find.ancestor(of: find.text('纯伴奏'), matching: find.byType(ListTile)),
      );
      expect(instrumental.enabled, isFalse);
      expect(instrumental.onTap, isNull);
      final original = tester.widget<ListTile>(
        find.ancestor(of: find.text('原唱伴唱'), matching: find.byType(ListTile)),
      );
      expect(original.enabled, isTrue);
      await tester.tap(find.text('原唱伴唱'));
      await tester.pumpAndSettle();
      expect(selection?.mode, KtvBackingMode.guideVocal);
      expect(selection?.sourcePath, 'song.wav');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('existing instrumental remains selectable', (tester) async {
    KtvEntrySelection? selection;
    await tester.pumpWidget(
      _SheetHost(
        asset: const AudioAsset(
          originalPath: 'song.wav',
          instrumentalPath: 'backing.wav',
          format: 'wav',
        ),
        onSelected: (mode) => selection = mode,
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.textContaining('纯伴奏暂不可用'), findsNothing);
    final instrumental = tester.widget<ListTile>(
      find.ancestor(of: find.text('纯伴奏'), matching: find.byType(ListTile)),
    );
    expect(instrumental.enabled, isTrue);
    await tester.tap(find.text('纯伴奏'));
    await tester.pumpAndSettle();
    expect(selection?.mode, KtvBackingMode.instrumental);
    expect(selection?.sourcePath, 'backing.wav');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a separated accompaniment says it was separated (D-060)', (
    tester,
  ) async {
    KtvEntrySelection? selection;
    await tester.pumpWidget(
      _SheetHost(
        asset: AudioAsset(
          originalPath: 'song.wav',
          instrumentalPath: 'stems/run-1/accompaniment.wav',
          format: 'wav',
          metadata: {
            AutomaticAccompaniment.metadataKey: AutomaticAccompaniment(
              path: 'stems/run-1/accompaniment.wav',
              generatedAt: DateTime.utc(2026, 11, 22),
            ).toJson(),
          },
        ),
        onSelected: (mode) => selection = mode,
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('播放从原曲自动分离的伴奏，可能残留少量人声'), findsOneWidget);
    expect(find.text('播放工程中的伴奏轨'), findsNothing);
    await tester.tap(find.text('纯伴奏'));
    await tester.pumpAndSettle();
    expect(selection?.sourcePath, 'stems/run-1/accompaniment.wav');
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.asset, required this.onSelected});

  final AudioAsset asset;
  final ValueChanged<KtvEntrySelection?> onSelected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final selected = await showModalBottomSheet<KtvEntrySelection>(
                  context: context,
                  showDragHandle: true,
                  useSafeArea: true,
                  builder: (_) => KtvEntrySheet(
                    audioAsset: asset,
                    currentSource: AudioSourceType.original,
                  ),
                );
                onSelected(selected);
              },
              child: const Text('打开'),
            );
          },
        ),
      ),
    );
  }
}
