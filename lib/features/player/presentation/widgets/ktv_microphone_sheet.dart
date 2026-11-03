import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
import 'ktv_control_label.dart';
import 'playback_error_banner.dart';

/// Microphone input, monitoring and the three volumes, as a modal sheet.
///
/// Moved here from `_KtvAudioControlsSheet`, a private widget of the deleted
/// fullscreen KTV view. The behaviour is deliberately unchanged — including
/// [recordingLocked], which freezes device switching and the backing volume
/// while a take is being recorded.
class KtvMicrophoneSheet extends StatelessWidget {
  final KtvMicrophoneService microphoneService;
  final AudioPlayerService audioService;

  /// Snapshot taken when the sheet opens: a modal sheet covers the record
  /// button, so the lock cannot change underneath it.
  final bool recordingLocked;

  const KtvMicrophoneSheet({
    super.key,
    required this.microphoneService,
    required this.audioService,
    required this.recordingLocked,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return StreamBuilder<KtvMicrophoneState>(
      stream: microphoneService.stateStream,
      initialData: microphoneService.currentState,
      builder: (context, microphoneSnapshot) {
        final microphone =
            microphoneSnapshot.data ?? microphoneService.currentState;
        return StreamBuilder<PlaybackState>(
          stream: audioService.stateStream,
          initialData: audioService.currentState,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data ?? audioService.currentState;
            final engineMs = microphone.engineLatency?.inMilliseconds;
            final extraMs = microphone.monitorDelay.inMilliseconds;
            final totalMs = engineMs == null ? null : engineMs + extraMs;
            const systemDefaultDeviceId = '__system_default__';
            final selectedDeviceId = microphone.selectedInputDeviceId;
            final selectedDeviceValue =
                selectedDeviceId != null &&
                    microphone.inputDevices.any(
                      (device) => device.id == selectedDeviceId,
                    )
                ? selectedDeviceId
                : systemDefaultDeviceId;
            final selectedDevice = microphone.selectedInputDevice;
            final deviceControlsLocked =
                recordingLocked ||
                microphone.isStarting ||
                microphone.isRefreshingInputDevices;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                spec.pageGutter,
                AppSpacing.sm,
                spec.pageGutter,
                AppSpacing.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.mic_rounded,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '麦克风与演唱音量',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '麦克风监听与歌曲播放使用独立音量。建议佩戴耳机或使用独立监听设备，扬声器直出可能产生啸叫。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '麦克风输入设备',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          SizedBox(
                            width: spec.minimumInteractiveExtent,
                            height: spec.minimumInteractiveExtent,
                            child: IconButton(
                              tooltip: recordingLocked
                                  ? '录音期间不能刷新麦克风设备'
                                  : '刷新麦克风设备',
                              onPressed: deviceControlsLocked
                                  ? null
                                  : () => unawaited(
                                      microphoneService.refreshInputDevices(),
                                    ),
                              icon: microphone.isRefreshingInputDevices
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.mic_external_on_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMedium,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedDeviceValue,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(
                                value: systemDefaultDeviceId,
                                child: Text('系统默认'),
                              ),
                              ...microphone.inputDevices.map(
                                (device) => DropdownMenuItem<String>(
                                  value: device.id,
                                  child: Text(
                                    device.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: deviceControlsLocked
                                ? null
                                : (value) => unawaited(
                                    microphoneService.selectInputDevice(
                                      value == systemDefaultDeviceId
                                          ? null
                                          : value,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        recordingLocked
                            ? '正在录制 take，输入设备已锁定；停止录音后可切换。'
                            : selectedDevice == null
                            ? microphone.inputDevices.isEmpty
                                  ? '未发现可选麦克风，将继续使用系统默认输入；可点击刷新重新扫描。'
                                  : '当前跟随系统默认输入设备；也可以固定选择某个麦克风。'
                            : '当前：${selectedDevice.label}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: recordingLocked
                              ? AppColors.warning
                              : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: microphone.isMonitoring,
                        onChanged: microphone.isStarting || recordingLocked
                            ? null
                            : (enabled) {
                                unawaited(
                                  enabled
                                      ? microphoneService.startMonitoring()
                                      : microphoneService.stopMonitoring(),
                                );
                              },
                        secondary: microphone.isStarting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                microphone.isMonitoring
                                    ? Icons.hearing_rounded
                                    : Icons.hearing_disabled_rounded,
                              ),
                        title: const Text('实时麦克风监听'),
                        subtitle: Text(
                          microphone.isMonitoring
                              ? '正在把麦克风输入低延迟送到当前输出设备'
                              : '开启后系统会请求麦克风权限',
                        ),
                      ),
                      if (microphone.error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        PlaybackErrorBanner(message: microphone.error!),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '麦克风电平',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      LinearProgressIndicator(
                        value: microphone.inputLevel.clamp(0.0, 1.0).toDouble(),
                        minHeight: 7,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      KtvControlLabel(
                        title: '麦克风音量',
                        value: '${(microphone.micGain * 100).round()}%',
                      ),
                      Slider(
                        value: microphone.micGain.clamp(0.0, 2.0).toDouble(),
                        min: 0,
                        max: 2,
                        divisions: 20,
                        onChanged: (value) =>
                            unawaited(microphoneService.setMicGain(value)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      KtvControlLabel(
                        title: '歌曲音量',
                        value: '${(playback.volume * 100).round()}%',
                      ),
                      Slider(
                        value: playback.volume.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: recordingLocked
                            ? null
                            : (value) =>
                                  unawaited(audioService.setVolume(value)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      KtvControlLabel(title: '监听附加延迟', value: '${extraMs}ms'),
                      Slider(
                        value: extraMs.clamp(0, 250).toDouble(),
                        min: 0,
                        max: 250,
                        divisions: 25,
                        onChanged: (value) => unawaited(
                          microphoneService.setMonitorDelay(
                            Duration(milliseconds: value.round()),
                          ),
                        ),
                      ),
                      Text(
                        totalMs == null
                            ? '设备未报告稳定的硬件延迟；这里的数值只增加软件监听延迟。'
                            : '音频引擎约 ${engineMs}ms + 附加 ${extraMs}ms = 约 ${totalMs}ms。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
