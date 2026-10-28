# 架构设计：音频播放器与跨端传输

## 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         Presentation Layer                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │PlayerScreen  │  │MiniPlayerBar │  │TransferProjectDialog │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │QuickPlayPage │  │ReceivePage   │  │PlayHistoryPage       │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Domain Layer                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  AudioPlayerService (接口)                 │  │
│  │  - loadAudio(String path)                                 │  │
│  │  - play() / pause() / stop()                              │  │
│  │  - seek(Duration position)                                │  │
│  │  - switchSource(AudioSource source)                       │  │
│  │  - Stream<PlaybackState> get stateStream                  │  │
│  │  - Stream<Duration> get positionStream                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  ProjectTransferService (接口)             │  │
│  │  - startServer(ProjectManifest project)                   │  │
│  │  - stopServer()                                           │  │
│  │  - String getQrCodeData()                                 │  │
│  │  - Stream<TransferProgress> get progressStream           │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                      PlayHistoryRepository (接口)          │  │
│  │  - addToHistory(String projectId)                         │  │
│  │  - List<PlayHistory> getRecentPlays(int limit)           │  │
│  │  - clearHistory()                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                           Data Layer                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
│  │ JustAudioPlayerService   │  │ HttpProjectTransferService   │ │
│  │ (just_audio 实现)         │  │ (shelf + qr_flutter)         │ │
│  └──────────────────────────┘  └──────────────────────────────┘ │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
│  │ FilePlayHistoryRepository│  │ HivePlayHistoryRepository    │ │
│  │ (文件存储)                │  │ (移动端 Hive)                │ │
│  └──────────────────────────┘  └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 领域模型扩展

### 1. AudioSource 枚举
```dart
enum AudioSource {
  original,      // 原声
  instrumental, // 伴奏
  vocals,        // 人声
}
```

### 2. PlaybackState 类
```dart
class PlaybackState {
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final AudioSource currentSource;
  final double speed;
  final double volume;
  
  const PlaybackState({
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
    required this.duration,
    required this.currentSource,
    this.speed = 1.0,
    this.volume = 1.0,
  });
}
```

### 3. PlayHistory 类
```dart
class PlayHistory {
  final String projectId;
  final String projectName;
  final DateTime playedAt;
  final Duration? lastPosition;
  final PlayMode playMode;
  
  const PlayHistory({
    required this.projectId,
    required this.projectName,
    required this.playedAt,
    this.lastPosition,
    this.playMode = PlayMode.ktv,
  });
}
```

### 4. TransferProgress 类
```dart
class TransferProgress {
  final TransferStatus status;
  final int bytesTransferred;
  final int totalBytes;
  final double get progressPercent;
  final String? error;
  
  const TransferProgress({
    required this.status,
    required this.bytesTransferred,
    required this.totalBytes,
    this.error,
  });
}

enum TransferStatus {
  idle,
  starting,
  transferring,
  completed,
  failed,
}
```

## 服务接口设计

### AudioPlayerService (领域接口)
```dart
abstract class AudioPlayerService {
  // 加载音频
  Future<void> loadAudio(String path, {AudioSource source = AudioSource.original});
  
  // 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  
  // 切换音源
  Future<void> switchSource(AudioSource source);
  
  // 播放参数
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  
  // 状态流
  Stream<PlaybackState> get stateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  
  // 当前状态
  PlaybackState get currentState;
  
  // 清理
  Future<void> dispose();
}
```

### ProjectTransferService (领域接口)
```dart
abstract class ProjectTransferService {
  // 发送端
  Future<void> startServer(ProjectManifest project);
  Future<void> stopServer();
  String getQrCodeData();
  Stream<TransferProgress> get serverProgressStream;
  
  // 接收端
  Future<void> connect(String qrCodeData);
  Future<ProjectManifest> receiveProject();
  Stream<TransferProgress> get clientProgressStream;
  
  // 状态
  bool get isServerRunning;
  bool get isReceiving;
}
```

## 数据模型更新

### ProjectManifest 扩展
```dart
class ProjectManifest {
  // ... 现有字段 ...
  
  // 新增
  final bool isQuickPlay;           // 是否快速播放模式
  final DateTime? lastPlayedAt;     // 上次播放时间
  final PlayMode preferredPlayMode; // 用户偏好播放模式
  
  // 音频源路径
  final AudioAsset audioAsset;      // 扩展为支持多音源
}
```

### AudioAsset 扩展
```dart
class AudioAsset {
  final String? originalPath;      // 原声
  final String? instrumentalPath;  // 伴奏
  final String? vocalsPath;        // 人声
  final AudioSource defaultSource; // 默认播放源
  
  String? get pathForCurrentSource => switch (defaultSource) {
    AudioSource.original => originalPath,
    AudioSource.instrumental => instrumentalPath,
    AudioSource.vocals => vocalsPath,
  };
  
  bool get hasOriginal => originalPath != null;
  bool get hasInstrumental => instrumentalPath != null;
  bool get hasVocals => vocalsPath != null;
}
```

## 文件存储结构

### 桌面端 (Desktop)
```
~/LyricForge/
├── Projects/
│   ├── {project_id}/
│   │   ├── manifest.json          # 工程元数据
│   │   ├── audio/
│   │   │   ├── original.mp3      # 原声
│   │   │   ├── instrumental.mp3  # 伴奏
│   │   │   └── vocals.mp3        # 人声
│   │   └── lyrics/
│   │       └── lyrics.json       # 歌词时间轴
│   └── ...
├── Temp/                         # 临时文件
└── Cache/                        # 音频缓存
```

### 移动端 (iOS/Android)
```
Documents/LyricForge/ (iOS) 或 ExternalStorage/LyricForge/ (Android)
├── Projects/
│   └── {project_id}/
│       ├── manifest.json
│       ├── audio/
│       │   ├── original.mp3
│       │   ├── instrumental.mp3
│       │   └── vocals.mp3
│       └── lyrics/
│           └── lyrics.json
├── Temp/
└── Cache/
```

## 跨端传输协议

### 传输流程
```
┌─────────────┐                           ┌─────────────┐
│ Desktop     │                           │ Mobile      │
│ (发送端)     │                           │ (接收端)     │
└──────┬──────┘                           └──────┬──────┘
       │                                         │
       │  1. 启动 HTTP Server                    │
       │     绑定到 0.0.0.0:随机端口              │
       │                                         │
       │  2. 生成二维码                          │
       │     数据: {"ip": "192.168.x.x",         │
       │            "port": 8080,                │
       │            "token": "xxx",              │
       │            "project_id": "xxx"}         │
       │                                         │
       │  3. 显示二维码等待扫描 ──────────────────>│ 扫描二维码
       │                                         │
       │  4. 校验 token                          │ 4. 发送 GET /connect
       │     <────────────────────────────────────│    携带 token
       │                                         │
       │  5. 打包工程为 .lyricforge               │
       │                                         │
       │  6. 发送文件流 <─────────────────────────│ 6. GET /download
       │     Content-Type: application/zip       │    下载并解压
       │     Content-Length: xxx                 │
       │                                         │
       │  7. 传输完成关闭连接                     │ 7. 导入工程
       │                                         │
       ▼                                         ▼
```

### API 端点
```
POST /connect
  Body: {token: string}
  Response: {status: "ok", project: ProjectMetadata}

GET /download
  Headers: {Authorization: Bearer {token}}
  Response: application/zip (工程文件)

GET /progress
  Response: text/event-stream (传输进度)
```

## 状态管理策略

### PlayerBloc (BLoC 模式)
```dart
// 事件
abstract class PlayerEvent {}
class Play extends PlayerEvent {}
class Pause extends PlayerEvent {}
class Seek extends PlayerEvent { final Duration position; }
class SwitchSource extends PlayerEvent { final AudioSource source; }
class ToggleLyrics extends PlayerEvent {}

// 状态
class PlayerState {
  final PlaybackState playbackState;
  final bool showLyrics;
  final LyricDocument? lyrics;
  final LyricLine? currentLine;
  
  const PlayerState({
    required this.playbackState,
    this.showLyrics = true,
    this.lyrics,
    this.currentLine,
  });
}
```

## 依赖清单

### 新增依赖
```yaml
dependencies:
  # 音频播放
  just_audio: ^0.10.5
  just_audio_background: ^0.0.1-beta.15
  audio_session: ^0.1.24
  
  # 桌面端音频支持
  just_audio_media_kit: ^0.0.1
  media_kit_libs_windows_audio: ^1.0.9
  media_kit_libs_linux: ^1.0.9
  
  # 本地存储
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  
  # 跨端传输
  shelf: ^1.4.1
  shelf_router: ^1.1.4
  http: ^1.2.0
  
  # 二维码
  qr_flutter: ^4.1.0
  mobile_scanner: ^3.5.5
  
  # 状态管理
  flutter_bloc: ^8.1.3
  
  # 权限
  permission_handler: ^11.3.0
  
dev_dependencies:
  hive_generator: ^2.0.1
  build_runner: ^2.4.8
```

## 实现顺序

### Phase 1.1: 工程文件系统 (高优先级)
1. 扩展 AudioAsset 模型
2. 创建 FileProjectRepository
3. 修改 ImportAudioScreen 复制文件到工程目录

### Phase 1.2: 音频播放器服务 (高优先级)
1. 创建 AudioPlayerService 接口
2. 实现 JustAudioPlayerService
3. 添加 just_audio 依赖

### Phase 1.3: PlayerScreen 重构 (高优先级)
1. 接入真实音频播放
2. 实现 Spotify 风格 UI
3. 添加进度条和播放控制

### Phase 1.4: 播放模式切换 (中优先级)
1. 原声/伴奏/人声切换
2. 歌词开关
3. 快速播放模式

### Phase 2.1: 跨端传输 - 发送端 (中优先级)
1. HTTP Server 实现
2. 二维码生成
3. 打包传输

### Phase 2.2: 跨端传输 - 接收端 (中优先级)
1. 二维码扫描
2. 文件下载
3. 工程导入
