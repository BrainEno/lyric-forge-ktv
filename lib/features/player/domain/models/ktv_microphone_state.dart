class KtvAudioInputDevice {
  final String id;
  final String label;
  final List<int> sampleRates;

  const KtvAudioInputDevice({
    required this.id,
    required this.label,
    this.sampleRates = const [],
  });
}

class KtvMicrophoneState {
  final bool isStarting;
  final bool isMonitoring;
  final bool permissionDenied;
  final bool isRefreshingInputDevices;
  final List<KtvAudioInputDevice> inputDevices;
  final String? selectedInputDeviceId;
  final double micGain;
  final Duration monitorDelay;
  final double inputLevel;
  final Duration? engineLatency;
  final String? error;

  const KtvMicrophoneState({
    this.isStarting = false,
    this.isMonitoring = false,
    this.permissionDenied = false,
    this.isRefreshingInputDevices = false,
    this.inputDevices = const [],
    this.selectedInputDeviceId,
    this.micGain = 1.0,
    this.monitorDelay = Duration.zero,
    this.inputLevel = 0,
    this.engineLatency,
    this.error,
  });

  KtvAudioInputDevice? get selectedInputDevice {
    final selectedId = selectedInputDeviceId;
    if (selectedId == null) return null;
    for (final device in inputDevices) {
      if (device.id == selectedId) return device;
    }
    return null;
  }

  KtvMicrophoneState copyWith({
    bool? isStarting,
    bool? isMonitoring,
    bool? permissionDenied,
    bool? isRefreshingInputDevices,
    List<KtvAudioInputDevice>? inputDevices,
    String? selectedInputDeviceId,
    bool clearSelectedInputDevice = false,
    double? micGain,
    Duration? monitorDelay,
    double? inputLevel,
    Duration? engineLatency,
    bool clearEngineLatency = false,
    String? error,
    bool clearError = false,
  }) {
    return KtvMicrophoneState(
      isStarting: isStarting ?? this.isStarting,
      isMonitoring: isMonitoring ?? this.isMonitoring,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      isRefreshingInputDevices:
          isRefreshingInputDevices ?? this.isRefreshingInputDevices,
      inputDevices: inputDevices ?? this.inputDevices,
      selectedInputDeviceId: clearSelectedInputDevice
          ? null
          : (selectedInputDeviceId ?? this.selectedInputDeviceId),
      micGain: micGain ?? this.micGain,
      monitorDelay: monitorDelay ?? this.monitorDelay,
      inputLevel: inputLevel ?? this.inputLevel,
      engineLatency:
          clearEngineLatency ? null : (engineLatency ?? this.engineLatency),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

double clampKtvMicGain(double value) => value.clamp(0.0, 2.0).toDouble();

Duration clampKtvMonitorDelay(Duration value) {
  const maximum = Duration(milliseconds: 250);
  if (value.isNegative) return Duration.zero;
  if (value > maximum) return maximum;
  return value;
}
