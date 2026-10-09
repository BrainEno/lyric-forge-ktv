import '../../../project/domain/models/audio_asset.dart';

class KtvRecordingSession {
  final String id;
  final String projectId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final AudioSourceType backingSource;
  final String backingPath;
  final Duration startPosition;
  final Duration duration;
  final String micStemPath;
  final String manifestPath;
  final String? mixedOutputPath;
  final double backingVolume;
  final double monitorMicGain;
  final bool alignmentReliable;
  final String? alignmentIssue;

  const KtvRecordingSession({
    required this.id,
    required this.projectId,
    required this.startedAt,
    this.completedAt,
    required this.backingSource,
    required this.backingPath,
    required this.startPosition,
    required this.duration,
    required this.micStemPath,
    required this.manifestPath,
    this.mixedOutputPath,
    required this.backingVolume,
    required this.monitorMicGain,
    this.alignmentReliable = true,
    this.alignmentIssue,
  });

  KtvRecordingSession copyWith({
    DateTime? completedAt,
    Duration? duration,
    String? mixedOutputPath,
    bool? alignmentReliable,
    String? alignmentIssue,
  }) {
    return KtvRecordingSession(
      id: id,
      projectId: projectId,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      backingSource: backingSource,
      backingPath: backingPath,
      startPosition: startPosition,
      duration: duration ?? this.duration,
      micStemPath: micStemPath,
      manifestPath: manifestPath,
      mixedOutputPath: mixedOutputPath ?? this.mixedOutputPath,
      backingVolume: backingVolume,
      monitorMicGain: monitorMicGain,
      alignmentReliable: alignmentReliable ?? this.alignmentReliable,
      alignmentIssue: alignmentIssue ?? this.alignmentIssue,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'projectId': projectId,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'backingSource': backingSource.name,
        'backingPath': backingPath,
        'startPositionMs': startPosition.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'micStemPath': micStemPath,
        'manifestPath': manifestPath,
        'mixedOutputPath': mixedOutputPath,
        'backingVolume': backingVolume,
        'monitorMicGain': monitorMicGain,
        'alignmentReliable': alignmentReliable,
        'alignmentIssue': alignmentIssue,
      };

  factory KtvRecordingSession.fromJson(Map<String, dynamic> json) {
    return KtvRecordingSession(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      backingSource: AudioSourceType.values.byName(json['backingSource'] as String),
      backingPath: json['backingPath'] as String,
      startPosition: Duration(milliseconds: json['startPositionMs'] as int),
      duration: Duration(milliseconds: json['durationMs'] as int),
      micStemPath: json['micStemPath'] as String,
      manifestPath: json['manifestPath'] as String,
      mixedOutputPath: json['mixedOutputPath'] as String?,
      backingVolume: (json['backingVolume'] as num).toDouble(),
      monitorMicGain: (json['monitorMicGain'] as num).toDouble(),
      alignmentReliable: json['alignmentReliable'] as bool? ?? true,
      alignmentIssue: json['alignmentIssue'] as String?,
    );
  }
}

class KtvRecordingState {
  final bool isRecording;
  final bool isExporting;
  final Duration recordedDuration;
  final KtvRecordingSession? currentSession;
  final KtvRecordingSession? lastCompletedSession;
  final String? error;

  const KtvRecordingState({
    this.isRecording = false,
    this.isExporting = false,
    this.recordedDuration = Duration.zero,
    this.currentSession,
    this.lastCompletedSession,
    this.error,
  });

  KtvRecordingState copyWith({
    bool? isRecording,
    bool? isExporting,
    Duration? recordedDuration,
    KtvRecordingSession? currentSession,
    bool clearCurrentSession = false,
    KtvRecordingSession? lastCompletedSession,
    String? error,
    bool clearError = false,
  }) {
    return KtvRecordingState(
      isRecording: isRecording ?? this.isRecording,
      isExporting: isExporting ?? this.isExporting,
      recordedDuration: recordedDuration ?? this.recordedDuration,
      currentSession:
          clearCurrentSession ? null : (currentSession ?? this.currentSession),
      lastCompletedSession:
          lastCompletedSession ?? this.lastCompletedSession,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class KtvRecordingException implements Exception {
  final String message;
  const KtvRecordingException(this.message);

  @override
  String toString() => message;
}
