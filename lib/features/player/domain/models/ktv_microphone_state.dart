class KtvMicrophoneState {
  final bool isStarting;
  final bool isMonitoring;
  final bool permissionDenied;
  final double micGain;
  final Duration monitorDelay;
  final double inputLevel;
  final Duration? engineLatency;
  final String? error;

  const KtvMicrophoneState({
    this.isStarting = false,
    this.isMonitoring = false,
    this.permissionDenied = false,
    this.micGain = 1.0,
    this.monitorDelay = Duration.zero,
    this.inputLevel = 0,
    this.engineLatency,
    this.error,
  });

  KtvMicrophoneState copyWith({
    bool? isStarting,
    bool? isMonitoring,
    bool? permissionDenied,
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
