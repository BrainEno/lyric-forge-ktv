import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_backing_mode.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_entry_sheet.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets('missing instrumental shows realistic guidance at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      KtvBackingMode? selection;
      await tester.pumpWidget(
        _SheetHost(
          asset: const AudioAsset(originalPath: 'song.wav', format: 'wav'),
          onSelected: (mode) => selection = mode,
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('纯伴奏暂不可用：可在桌面端工程详情导入已有伴奏，或继续使用原唱伴唱。'), findsOneWidget);
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
      expect(selection, KtvBackingMode.guideVocal);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('existing instrumental remains selectable', (tester) async {
    KtvBackingMode? selection;
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
    expect(selection, KtvBackingMode.instrumental);
    expect(tester.takeException(), isNull);
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.asset, required this.onSelected});

  final AudioAsset asset;
  final ValueChanged<KtvBackingMode?> onSelected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final selected = await showModalBottomSheet<KtvBackingMode>(
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
