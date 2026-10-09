import '../models/ktv_microphone_state.dart';

abstract class KtvMicrophoneService {
  Stream<KtvMicrophoneState> get stateStream;
  KtvMicrophoneState get currentState;

  Future<void> startMonitoring();
  Future<void> stopMonitoring();
  Future<void> setMicGain(double gain);
  Future<void> setMonitorDelay(Duration delay);
  Future<void> dispose();
}
