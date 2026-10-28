# Phase 1.3: PlayerScreen 重构 - 最终实施计划

## 目标
将 PlayerScreen 从 Timer 模拟播放重构为使用 just_audio 的真实音频播放器，接入 Spotify 风格 UI，支持原声/伴奏/人声切换。

---

## 任务清单（按执行顺序）

### 任务 1: 添加 just_audio 依赖
**文件**: `pubspec.yaml`
**变更**:
```yaml
dependencies:
  # 新增音频播放
  just_audio: ^0.10.5
  just_audio_background: ^0.0.1-beta.15
  audio_session: ^0.1.24
```
**macOS 注意**: 需要在 `macos/Runner/DebugProfile.entitlements` 和 `macos/Runner/Release.entitlements` 中添加网络权限：
```xml
<key>com.apple.security.network.client</key>
<true/>
```

---

### 任务 2: 扩展 AudioAsset 模型
**文件**: `lib/features/project/domain/models/audio_asset.dart`
**新增**:
```dart
/// 音频源类型
enum AudioSourceType {
  original,      // 原声
  instrumental, // 伴奏
  vocals,        // 人声
}

extension AudioAssetExtensions on AudioAsset {
  /// 获取指定音源的路径
  String? getPathForSource(AudioSourceType source) => switch (source) {
    AudioSourceType.original => originalPath,
    AudioSourceType.instrumental => instrumentalPath,
    AudioSourceType.vocals => vocalPath,
  };

  /// 检查音源是否可用
  bool hasSource(AudioSourceType source) => getPathForSource(source) != null;

  /// 获取默认音源（优先级：伴奏 > 原声 > 人声）
  AudioSourceType get defaultSource {
    if (instrumentalPath != null) return AudioSourceType.instrumental;
    if (originalPath != null) return AudioSourceType.original;
    if (vocalPath != null) return AudioSourceType.vocals;
    return AudioSourceType.original;
  }

  /// 获取所有可用音源列表
  List<AudioSourceType> get availableSources {
    return AudioSourceType.values.where(hasSource).toList();
  }
}
```

---

### 任务 3: 创建 PlaybackState 和 AudioPlayerService 接口
**文件**: `lib/features/player/domain/models/playback_state.dart`
**内容**:
```dart
import '../../../project/domain/models/audio_asset.dart';

/// 播放状态
class PlaybackState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final bool isLoading;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;
  final double speed;
  final double volume;
  final AudioSourceType? currentSource;
  final String? error;

  const PlaybackState({
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompleted,
    required this.isLoading,
    required this.position,
    this.duration,
    required this.bufferedPosition,
    required this.speed,
    required this.volume,
    this.currentSource,
    this.error,
  });

  /// 初始状态
  const PlaybackState.idle()
      : isPlaying = false,
        isBuffering = false,
        isCompleted = false,
        isLoading = false,
        position = Duration.zero,
        duration = null,
        bufferedPosition = Duration.zero,
        speed = 1.0,
        volume = 1.0,
        currentSource = null,
        error = null;

  /// 当前进度百分比 (0.0 - 1.0)
  double get progressPercent {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration!.inMilliseconds;
  }

  /// 缓冲进度百分比
  double get bufferedPercent {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return bufferedPosition.inMilliseconds / duration!.inMilliseconds;
  }

  /// 格式化当前位置
  String get formattedPosition => _formatDuration(position);

  /// 格式化总时长
  String get formattedDuration => duration != null 
      ? _formatDuration(duration!) 
      : '--:--';

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  PlaybackState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    double? volume,
    AudioSourceType? currentSource,
    String? error,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      currentSource: currentSource ?? this.currentSource,
      error: error ?? this.error,
    );
  }
}
```

**文件**: `lib/features/player/domain/services/audio_player_service.dart`
**内容**:
```dart
import 'dart:async';

import '../../../project/domain/models/audio_asset.dart';
import '../models/playback_state.dart';

/// 音频播放器服务接口
abstract class AudioPlayerService {
  /// 加载工程音频
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  });

  /// 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// 切换音源
  Future<void> switchSource(AudioSourceType source);

  /// 播放参数
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);

  /// 状态流
  Stream<PlaybackState> get stateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// 当前状态
  PlaybackState get currentState;

  /// 释放资源
  Future<void> dispose();
}
```

---

### 任务 4: 实现 JustAudioPlayerService
**文件**: `lib/features/player/data/services/just_audio_player_service.dart`
**内容**:
```dart
import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';

class JustAudioPlayerService implements AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  AudioAsset? _currentAsset;
  AudioSourceType? _currentSource;

  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _currentState = const PlaybackState.idle();

  JustAudioPlayerService() {
    _initStateStreams();
  }

  void _initStateStreams() {
    // 合并 just_audio 的多个流
    Rx.combineLatest4<
      PlayerState,
      Duration,
      Duration?,
      Duration,
      _InternalState
    >(
      _player.playerStateStream,
      _player.positionStream,
      _player.durationStream,
      _player.bufferedPositionStream,
      (playerState, position, duration, buffered) => _InternalState(
        playerState: playerState,
        position: position,
        duration: duration,
        bufferedPosition: buffered,
      ),
    ).listen(_updateState);
  }

  void _updateState(_InternalState internal) {
    final isLoading = internal.playerState.processingState == ProcessingState.loading;
    final isBuffering = internal.playerState.processingState == ProcessingState.buffering;
    final isCompleted = internal.playerState.processingState == ProcessingState.completed;
    
    _currentState = PlaybackState(
      isPlaying: internal.playerState.playing,
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      isLoading: isLoading,
      position: internal.position,
      duration: internal.duration,
      bufferedPosition: internal.bufferedPosition,
      speed: _player.speed,
      volume: _player.volume,
      currentSource: _currentSource,
      error: internal.playerState.error?.toString(),
    );
    
    _stateController.add(_currentState);
  }

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    _currentAsset = audioAsset;

    // 按优先级选择可用音源
    AudioSourceType source = preferredSource;
    if (!audioAsset.hasSource(source)) {
      source = audioAsset.defaultSource;
    }

    await _loadSource(source);
  }

  Future<void> _loadSource(AudioSourceType source) async {
    if (_currentAsset == null) return;

    final path = _currentAsset!.getPathForSource(source);
    if (path == null) {
      throw Exception('Source $source not available');
    }

    _currentSource = source;
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> switchSource(AudioSourceType source) async {
    if (_currentAsset == null) return;
    if (!_currentAsset!.hasSource(source)) {
      throw Exception('Source $source not available for this project');
    }

    final wasPlaying = _player.playing;
    final currentPosition = _player.position;

    await _loadSource(source);
    await _player.seek(currentPosition);

    if (wasPlaying) {
      await _player.play();
    }
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  PlaybackState get currentState => _currentState;

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _player.dispose();
  }
}

/// 内部状态封装
class _InternalState {
  final PlayerState playerState;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;

  _InternalState({
    required this.playerState,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
  });
}
```

---

### 任务 5: 注册服务到 ServiceLocator
**文件**: `lib/core/services/service_locator.dart`
**变更**:
```dart
import '../../features/player/data/services/just_audio_player_service.dart';
import '../../features/player/domain/services/audio_player_service.dart';
import '../../features/project/data/repositories/memory_project_repository.dart';
import '../../features/project/domain/repositories/project_repository.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late final ProjectRepository projectRepository;
  late final AudioPlayerService audioPlayerService;

  void initialize() {
    projectRepository = MemoryProjectRepository();
    audioPlayerService = JustAudioPlayerService();
  }
}
```

---

### 任务 6: 重构 PlayerScreen
**文件**: `lib/features/player/presentation/screens/player_screen.dart`

**主要变更点**:
1. 移除 `Timer` 模拟，使用 `AudioPlayerService`
2. 使用 `StreamBuilder` 监听播放状态
3. 进度条显示真实音频时长和缓冲状态
4. 添加音源切换按钮
5. 添加加载状态显示

**新组件**:
- `_AudioSourceSelector`: 原声/伴奏/人声切换按钮组
- `_BufferedProgressBar`: 带缓冲显示的进度条
- `_LoadingOverlay`: 音频加载遮罩

---

## 文件变更汇总

| 操作 | 文件 | 行数 |
|------|------|------|
| 编辑 | `pubspec.yaml` | +8 |
| 编辑 | `lib/features/project/domain/models/audio_asset.dart` | +25 |
| 新建 | `lib/features/player/domain/models/playback_state.dart` | +85 |
| 新建 | `lib/features/player/domain/services/audio_player_service.dart` | +35 |
| 新建 | `lib/features/player/data/services/just_audio_player_service.dart` | +140 |
| 编辑 | `lib/core/services/service_locator.dart` | +10 |
| 编辑 | `lib/features/player/presentation/screens/player_screen.dart` | ~200 |
| **总计** | | **~500 行** |

---

## UI 设计（Spotify 风格）

### 音源切换按钮位置
放在播放控制栏上方（进度条和播放按钮之间）：

```
┌─────────────────────────────────────┐
│         [专辑封面占位]               │
├─────────────────────────────────────┤
│         歌曲标题                    │
│         艺术家                      │
├─────────────────────────────────────┤
│ [00:00]  ==========●=======  [03:45]│
├─────────────────────────────────────┤
│  [原声] [伴奏*] [人声]   ← 新增    │
├─────────────────────────────────────┤
│   ⏮️   ⏯️/▶️   ⏭️                    │
├─────────────────────────────────────┤
│ [歌词] [调速] [导出]               │
└─────────────────────────────────────┘
```

### 按钮样式
- 选中状态：背景色 `AppColors.accent`，文字白色
- 未选中状态：背景色透明，文字 `AppColors.textSecondary`
- 禁用状态：文字 `AppColors.textDisabled`，不可点击

---

## 验证清单

### 功能验证
- [ ] 导入音频后能在 PlayerScreen 播放
- [ ] 进度条显示真实音频时长
- [ ] 拖动进度条可以跳转到任意位置
- [ ] 点击播放/暂停按钮正常工作
- [ ] 可以切换原声/伴奏/人声（如果有）
- [ ] 切换音源时保持播放位置
- [ ] 音频播放完成后显示完成状态

### 代码验证
- [ ] `flutter pub get` 成功
- [ ] `flutter analyze` 无新错误
- [ ] 桌面端 (macOS) 能正常编译运行

### UI 验证
- [ ] 播放器 UI 符合 Spotify 暗色风格
- [ ] 音源切换按钮状态清晰
- [ ] 加载状态有视觉反馈

---

## 下一步行动

一旦确认此计划，我将按顺序执行：

1. **任务 1**: 添加 just_audio 依赖
2. **任务 2**: 扩展 AudioAsset
3. **任务 3**: 创建领域接口
4. **任务 4**: 实现 just_audio 服务
5. **任务 5**: 注册服务
6. **任务 6**: 重构 PlayerScreen

每个任务完成后我会：
- 运行 `flutter analyze` 验证
- 更新 `docs/work_log.md`
- 报告进度和任何遇到的问题

**请确认此计划后，我将立即开始实施！**
