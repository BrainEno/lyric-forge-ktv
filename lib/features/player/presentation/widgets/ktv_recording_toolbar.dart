import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/services/ktv_microphone_service.dart';
import '../../domain/services/ktv_recording_service.dart';
import '../recording_time_format.dart';

/// Record / history / microphone entry points for the fullscreen KTV surface.
///
/// These three buttons used to live in the unreachable `_FullScreenKtvView`,
/// so recording, exporting and the take history were built but impossible to
/// reach. They are now part of [ImmersiveKtvScreen] and deliberately dumb: the
/// widget owns no flow, it only renders the two service states and forwards
/// taps, which keeps the guards on the screen (and testable there).
class KtvRecordingToolbar extends StatelessWidget {
  static const historyButtonKey = Key('ktv_take_history_button');
  static const recordButtonKey = Key('ktv_record_button');
  static const microphoneButtonKey = Key('ktv_microphone_button');

  final KtvRecordingService recordingService;
  final KtvMicrophoneService microphoneService;
  final VoidCallback onOpenHistory;
  final VoidCallback onToggleRecording;
  final VoidCallback onOpenMicrophone;

  /// Disables every entry point while the project is still loading.
  final bool enabled;

  const KtvRecordingToolbar({
    super.key,
    required this.recordingService,
    required this.microphoneService,
    required this.onOpenHistory,
    required this.onToggleRecording,
    required this.onOpenMicrophone,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return StreamBuilder<KtvRecordingState>(
      stream: recordingService.stateStream,
      initialData: recordingService.currentState,
      builder: (context, recordingSnapshot) {
        final recording = recordingSnapshot.data ?? recordingService.currentState;
        // Recording and exporting both rewrite the take directory, so neither
        // may be interrupted by another one starting on top of it.
        final takeBusy = recording.isRecording || recording.isExporting;
        return StreamBuilder<KtvMicrophoneState>(
          stream: microphoneService.stateStream,
          initialData: microphoneService.currentState,
          builder: (context, microphoneSnapshot) {
            final microphone =
                microphoneSnapshot.data ?? microphoneService.currentState;
            final extent = spec.minimumInteractiveExtent;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: extent,
                  height: extent,
                  child: IconButton.filledTonal(
                    key: historyButtonKey,
                    tooltip: takeBusy ? '录音或导出期间不能查看演唱历史' : '演唱历史',
                    onPressed: enabled && !takeBusy ? onOpenHistory : null,
                    icon: const Icon(Icons.history_rounded),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (recording.isRecording)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: Text(
                      formatRecordingTime(recording.recordedDuration),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                SizedBox(
                  width: extent,
                  height: extent,
                  child: IconButton.filled(
                    key: recordButtonKey,
                    tooltip: recording.isRecording ? '停止录音' : '开始 KTV 录音',
                    onPressed: enabled && !recording.isExporting
                        ? onToggleRecording
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: recording.isRecording
                          ? AppColors.error
                          : AppColors.bgSurface,
                      foregroundColor: AppColors.pureWhite,
                    ),
                    icon: Icon(
                      recording.isRecording
                          ? Icons.stop_rounded
                          : Icons.fiber_manual_record_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: extent,
                  height: extent,
                  child: IconButton.filledTonal(
                    key: microphoneButtonKey,
                    tooltip: microphone.isMonitoring
                        ? '麦克风监听已开启'
                        : '麦克风与音量',
                    onPressed: enabled ? onOpenMicrophone : null,
                    icon: Icon(
                      microphone.isMonitoring
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Always-visible recording pill.
///
/// The control layer fades out with the chrome; a take that keeps running
/// behind hidden controls would be invisible and unstoppable, so the red dot
/// and elapsed time sit above the lyrics regardless of chrome visibility.
class KtvRecordingIndicator extends StatelessWidget {
  final KtvRecordingService recordingService;

  const KtvRecordingIndicator({super.key, required this.recordingService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<KtvRecordingState>(
      stream: recordingService.stateStream,
      initialData: recordingService.currentState,
      builder: (context, snapshot) {
        final recording = snapshot.data ?? recordingService.currentState;
        if (!recording.isRecording && !recording.isExporting) {
          return const SizedBox.shrink();
        }
        final label = recording.isRecording
            ? '录音中 ${formatRecordingTime(recording.recordedDuration)}'
            : '正在导出混音';
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.pureBlack.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  recording.isRecording
                      ? Icons.fiber_manual_record_rounded
                      : Icons.graphic_eq_rounded,
                  size: 14,
                  color: AppColors.error,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.pureWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
