from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:120]!r}")
    target.write_text(text.replace(old, new, 1))


replace_once(
    "pubspec.yaml",
    "  audio_session: ^0.2.4\n",
    "  audio_session: ^0.2.4\n  audio_io: ^0.6.1\n  permission_handler: ^12.0.3\n",
)

replace_once(
    "android/app/src/main/AndroidManifest.xml",
    '    <uses-permission android:name="android.permission.CAMERA"/>\n',
    '    <uses-permission android:name="android.permission.CAMERA"/>\n'
    '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n',
)

replace_once(
    "ios/Runner/Info.plist",
    "\t<key>NSCameraUsageDescription</key>\n\t<string>用于扫描 Elysium Player 桌面端生成的配对二维码。</string>\n",
    "\t<key>NSCameraUsageDescription</key>\n\t<string>用于扫描 Elysium Player 桌面端生成的配对二维码。</string>\n"
    "\t<key>NSMicrophoneUsageDescription</key>\n\t<string>用于 KTV 演唱时实时监听你的麦克风输入。</string>\n",
)

replace_once(
    "macos/Runner/Info.plist",
    "\t<key>NSMainNibFile</key>\n",
    "\t<key>NSMicrophoneUsageDescription</key>\n\t<string>用于 KTV 演唱时实时监听你的麦克风输入。</string>\n"
    "\t<key>NSMainNibFile</key>\n",
)

for entitlement in (
    "macos/Runner/DebugProfile.entitlements",
    "macos/Runner/Release.entitlements",
):
    replace_once(
        entitlement,
        "    <key>com.apple.security.app-sandbox</key>\n    <true/>\n",
        "    <key>com.apple.security.app-sandbox</key>\n    <true/>\n"
        "    <key>com.apple.security.device.audio-input</key>\n    <true/>\n",
    )

for podfile, flutter_settings in (
    ("ios/Podfile", "    flutter_additional_ios_build_settings(target)\n"),
    ("macos/Podfile", "    flutter_additional_macos_build_settings(target)\n"),
):
    replace_once(
        podfile,
        flutter_settings,
        flutter_settings
        + "    target.build_configurations.each do |config|\n"
        + "      definitions = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] || ['$(inherited)']\n"
        + "      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = definitions + ['PERMISSION_MICROPHONE=1']\n"
        + "    end\n",
    )

replace_once(
    "lib/core/services/service_locator.dart",
    "import '../../features/player/data/services/just_audio_player_service.dart';\n",
    "import '../../features/player/data/services/audio_io_ktv_microphone_service.dart';\n"
    "import '../../features/player/data/services/just_audio_player_service.dart';\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "import '../../features/player/domain/services/audio_player_service.dart';\n",
    "import '../../features/player/domain/services/audio_player_service.dart';\n"
    "import '../../features/player/domain/services/ktv_microphone_service.dart';\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "  late final AudioPlayerService audioPlayerService;\n",
    "  late final AudioPlayerService audioPlayerService;\n"
    "  late final KtvMicrophoneService ktvMicrophoneService;\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "    final rawAudioPlayer = JustAudioPlayerService();\n",
    "    final rawAudioPlayer = JustAudioPlayerService();\n"
    "    ktvMicrophoneService = AudioIoKtvMicrophoneService();\n",
)

replace_once(
    "lib/features/player/data/services/just_audio_player_service.dart",
    "  Future<void> setVolume(double volume) => _player.setVolume(volume);\n",
    "  Future<void> setVolume(double volume) async {\n"
    "    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());\n"
    "    _updateState();\n"
    "  }\n",
)

player = Path("lib/features/player/presentation/screens/player_screen.dart")
text = player.read_text()

old_import = """import '../../domain/models/ktv_backing_mode.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
"""
new_import = """import '../../domain/models/ktv_backing_mode.dart';
import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
"""
if old_import not in text:
    raise SystemExit("Player imports anchor not found")
text = text.replace(old_import, new_import, 1)

old_state = """class _FullScreenKtvViewState extends State<_FullScreenKtvView> {
  late ProjectManifest _project;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  int _projectLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    AppChromeController.enterImmersive();
"""
new_state = """class _FullScreenKtvViewState extends State<_FullScreenKtvView> {
  late ProjectManifest _project;
  late final KtvMicrophoneService _microphoneService;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  int _projectLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    _microphoneService = ServiceLocatorGlobal.I.ktvMicrophoneService;
    AppChromeController.enterImmersive();
"""
if old_state not in text:
    raise SystemExit("Fullscreen KTV state anchor not found")
text = text.replace(old_state, new_state, 1)

old_before_dispose = """    setState(() => _project = nextProject);
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    AppChromeController.exitImmersive();
"""
new_before_dispose = """    setState(() => _project = nextProject);
  }

  Future<void> _openMicrophoneControls() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvAudioControlsSheet(
        microphoneService: _microphoneService,
        audioService: widget.audioService,
      ),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    unawaited(_microphoneService.stopMonitoring());
    AppChromeController.exitImmersive();
"""
if old_before_dispose not in text:
    raise SystemExit("Fullscreen KTV dispose anchor not found")
text = text.replace(old_before_dispose, new_before_dispose, 1)

old_exit = """                            SizedBox(
                              width: spec.minimumInteractiveExtent,
                              height: spec.minimumInteractiveExtent,
                              child: IconButton.filledTonal(
                                tooltip: '退出全屏 KTV',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.fullscreen_exit_rounded),
                              ),
                            ),
"""
new_exit = """                            StreamBuilder<KtvMicrophoneState>(
                              stream: _microphoneService.stateStream,
                              initialData: _microphoneService.currentState,
                              builder: (context, microphoneSnapshot) {
                                final microphone = microphoneSnapshot.data ??
                                    _microphoneService.currentState;
                                return SizedBox(
                                  width: spec.minimumInteractiveExtent,
                                  height: spec.minimumInteractiveExtent,
                                  child: IconButton.filledTonal(
                                    tooltip: microphone.isMonitoring
                                        ? '麦克风监听已开启'
                                        : '麦克风与音量',
                                    onPressed: _openMicrophoneControls,
                                    icon: Icon(
                                      microphone.isMonitoring
                                          ? Icons.mic_rounded
                                          : Icons.mic_none_rounded,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: spec.minimumInteractiveExtent,
                              height: spec.minimumInteractiveExtent,
                              child: IconButton.filledTonal(
                                tooltip: '退出全屏 KTV',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.fullscreen_exit_rounded),
                              ),
                            ),
"""
if old_exit not in text:
    raise SystemExit("Fullscreen exit button anchor not found")
text = text.replace(old_exit, new_exit, 1)

sheet = """class _KtvAudioControlsSheet extends StatelessWidget {
  final KtvMicrophoneService microphoneService;
  final AudioPlayerService audioService;

  const _KtvAudioControlsSheet({
    required this.microphoneService,
    required this.audioService,
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
                          const Icon(Icons.mic_rounded, color: AppColors.accent),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '麦克风与演唱音量',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
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
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: microphone.isMonitoring,
                        onChanged: microphone.isStarting
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                        _PlaybackError(message: microphone.error!),
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
                      _KtvControlLabel(
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
                      _KtvControlLabel(
                        title: '歌曲音量',
                        value: '${(playback.volume * 100).round()}%',
                      ),
                      Slider(
                        value: playback.volume.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: (value) =>
                            unawaited(audioService.setVolume(value)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _KtvControlLabel(
                        title: '监听附加延迟',
                        value: '${extraMs}ms',
                      ),
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

class _KtvControlLabel extends StatelessWidget {
  final String title;
  final String value;

  const _KtvControlLabel({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

"""
anchor = "class _CompactSourceMenu extends StatelessWidget {"
if anchor not in text:
    raise SystemExit("Compact source menu anchor not found")
text = text.replace(anchor, sheet + anchor, 1)
player.write_text(text)
