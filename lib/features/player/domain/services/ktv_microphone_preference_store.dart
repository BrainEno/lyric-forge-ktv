abstract class KtvMicrophonePreferenceStore {
  Future<String?> loadPreferredInputDeviceId();

  Future<void> savePreferredInputDeviceId(String? deviceId);
}
