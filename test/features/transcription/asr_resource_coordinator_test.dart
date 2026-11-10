import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';

void main() {
  test('exclusive acquisition and stale releases cannot free a newer owner', () {
    final gate = AsrResourceCoordinator();
    expect(gate.activeUse, isNull);
    final first = gate.tryAcquire(AsrResourceUse.transcription)!;
    expect(gate.activeUse, AsrResourceUse.transcription);
    for (final use in AsrResourceUse.values) {
      expect(gate.tryAcquire(use), isNull);
    }
    first.release();
    final second = gate.tryAcquire(AsrResourceUse.alignment)!;
    first.release();
    expect(gate.activeUse, AsrResourceUse.alignment);
    expect(gate.tryAcquire(AsrResourceUse.installation), isNull);
    second.release();
    second.release();
    expect(gate.activeUse, isNull);
  });
}
