import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/pcm_delay_line.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_microphone_state.dart';

void main() {
  group('PcmDelayLine', () {
    test('applies microphone gain without delay', () {
      final line = PcmDelayLine(sampleRate: 1000, gain: 1.5);
      final output = line.process(<double>[0.2, -0.4, 0.9]);

      expect(output[0], closeTo(0.3, 1e-12));
      expect(output[1], closeTo(-0.6, 1e-12));
      expect(output[2], closeTo(1.0, 1e-12));
    });

    test('delays monitoring by the configured sample count', () {
      final line = PcmDelayLine(
        sampleRate: 1000,
        delay: const Duration(milliseconds: 2),
      );

      expect(line.process(<double>[0.25, 0.5]), <double>[0, 0]);
      expect(line.process(<double>[0.75, 1.0]), <double>[0.25, 0.5]);
    });

    test('changing delay resets buffered audio instead of replaying stale input', () {
      final line = PcmDelayLine(
        sampleRate: 1000,
        delay: const Duration(milliseconds: 1),
      );
      expect(line.process(<double>[0.5]), <double>[0]);

      line.setDelay(const Duration(milliseconds: 2));
      expect(line.process(<double>[0.8, 0.9]), <double>[0, 0]);
    });
  });

  test('KTV microphone controls clamp unsafe ranges', () {
    expect(clampKtvMicGain(-1), 0);
    expect(clampKtvMicGain(3), 2);
    expect(clampKtvMonitorDelay(const Duration(milliseconds: -20)), Duration.zero);
    expect(
      clampKtvMonitorDelay(const Duration(milliseconds: 500)),
      const Duration(milliseconds: 250),
    );
  });

  group('KtvMicrophoneState input devices', () {
    const usbMic = KtvAudioInputDevice(
      id: 'usb-mic',
      label: 'USB Microphone',
      sampleRates: <int>[44100, 48000],
    );
    const builtInMic = KtvAudioInputDevice(
      id: 'built-in',
      label: 'Built-in Microphone',
      sampleRates: <int>[48000],
    );

    test('resolves the selected input device by stable id', () {
      const state = KtvMicrophoneState(
        inputDevices: <KtvAudioInputDevice>[usbMic, builtInMic],
        selectedInputDeviceId: 'usb-mic',
      );

      expect(state.selectedInputDevice?.id, 'usb-mic');
      expect(state.selectedInputDevice?.label, 'USB Microphone');
    });

    test('returns null when the selected device disappeared', () {
      const state = KtvMicrophoneState(
        inputDevices: <KtvAudioInputDevice>[builtInMic],
        selectedInputDeviceId: 'usb-mic',
      );

      expect(state.selectedInputDevice, isNull);
    });

    test('can return to the operating-system default input', () {
      const state = KtvMicrophoneState(
        inputDevices: <KtvAudioInputDevice>[usbMic],
        selectedInputDeviceId: 'usb-mic',
      );

      final defaultState = state.copyWith(clearSelectedInputDevice: true);

      expect(defaultState.selectedInputDeviceId, isNull);
      expect(defaultState.selectedInputDevice, isNull);
      expect(defaultState.inputDevices, hasLength(1));
    });
  });
}
