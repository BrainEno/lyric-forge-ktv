# 架构设计：音频播放器与跨端传输

> 状态：本文是播放器 Phase 1 之前的**早期设计提案**，保留作历史参考；实现已与提案多处分叉。权威现状以 `pubspec.yaml`、`lib/features/` 的实际结构和 `AGENTS.md` 的架构规则为准。最后核对：2026-10-31 @ `afeb3bb`。
>
> 主要分叉（提案 → 已实现）：
> - 跨端传输：shelf HTTP 服务 → `dart:io` 的 `HttpServer.bindSecure`（TLS 证书指纹固定、Bearer 令牌），实现为 `HttpMediaHubService`；不绑定 `0.0.0.0`，只绑定局域网/Tailscale/loopback 接口。
> - 本地存储：移动端 Hive → 全平台统一的 JSON 文件存储，经 `AtomicJsonFile` 做校验、备份轮换与原子替换。
> - 状态管理：flutter_bloc/BLoC → 无第三方状态框架，使用 `setState` + `StreamController`，由 `lib/core/services/service_locator.dart` 集中装配。
> - 传输协议：`/connect`、`/download` → 见下文「API 端点（已实现）」的 `/v1/*` 接口。

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
│  │                  MediaHubService (接口)                    │  │
│  │  - startSharing(List<SharedAudioTrack>)                   │  │
│  │  - stopSharing()                                           │  │
│  │  - stateStream: Stream<MediaHubState>                      │  │
│  │  - MediaHubSession? get currentSession                   │  │
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
│  │ JustAudioPlayerService   │  │ HttpMediaHubService          │ │
│  │ (just_audio 实现)         │  │ (dart:io HTTPS 指纹固定)         │ │
│  └──────────────────────────┘  └──────────────────────────────┘ │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
│  │ FilePlayHistoryRepository│  │ AtomicJsonFile               │ │
│  │ (文件存储)                │  │ (全平台 JSON 原子写)                │ │
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

### MediaHubService (领域接口)

已实现的接口位于 `lib/features/transfer/domain/services/media_hub_service.dart`，实现位于 `lib/features/transfer/data/services/http_media_hub_service.dart`（配对/发现见同目录的 `discoverable_media_hub_service.dart`、二维码配对沿用 `qr_flutter` + `mobile_scanner`）：

```dart
abstract class MediaHubService {
  Future<MediaHubSession> startSharing(List<SharedAudioTrack> tracks);
  Future<void> stopSharing();
  Stream<MediaHubState> get stateStream;
  MediaHubState get currentState;
  MediaHubSession? get currentSession;
  bool get isRunning;
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

### 传输流程（已实现）

1. 桌面端调用 `startSharing(tracks)` 后，仅在局域网（RFC1918）、Tailscale（100.64/10）与 loopback 接口上以自签证书启动 HTTPS 监听（首选端口 48517，占用时回退随机端口），生成一次性随机会话令牌。
2. 移动端扫描二维码完成显式配对：二维码承载端点、会话令牌与服务端证书的 SHA 指纹；客户端在 TLS 握手时按指纹固定校验，不匹配即拒绝。
3. 已配对设备之间用 HMAC-SHA256 签名的 UDP 发现报文互相定位（每请求随机 nonce 防重放），原始发现 secret 永不出现在链路上。
4. 音频以 Bearer 头鉴权后按 HTTP Range 流式播放或下载；移动端回传走带大小/超时/并发/剩余空间限额的上传通道。

### API 端点（已实现）

```
GET  /v1/health                          会话与端点信息
GET  /v1/tracks                          已共享曲目清单
GET  /v1/tracks/{id}/audio               音频（支持单 Range / HEAD）
GET  /v1/tracks/{id}/artwork             封面
GET  /v1/tracks/{id}/lyrics              歌词
POST /v1/incoming/audio?filename=...     回传音频（2 GiB 等限额，见实现常量）

全部端点要求 Header: Authorization: Bearer {token}，且经证书指纹固定的 HTTPS。
```

## 状态管理策略（已实现）

未采用 BLoC 或任何第三方状态管理框架：界面状态以 `setState` 为主，播放/队列/会话等长生命周期状态由领域服务以 `Stream` 暴露，播放会话收敛为单一 app 级模型（`PlaybackSessionService`）；依赖装配集中在 `lib/core/services/service_locator.dart` 手工完成。相关取舍与后续重构诉求见 issue #235。

## 依赖清单（已实现快照，以 pubspec.yaml 为准）

```yaml
dependencies:
  # 音频播放
  just_audio: ^0.10.5
  just_audio_media_kit:          # vendored 分叉，见 packages/just_audio_media_kit
    path: packages/just_audio_media_kit
  media_kit_libs_windows_audio: ^1.0.9
  media_kit_libs_linux: ^1.2.1
  audio_service: ^0.18.19        # 系统媒体会话（替代提案中的 just_audio_background）
  audio_session: ^0.2.4

  # KTV 麦克风采集与低延迟监听
  record: 6.2.1
  flutter_soloud: 4.1.7          # pin 原因见 pubspec.yaml 注释与决策 D-002

  # 本地存储：无第三方数据库；JSON 文件 + AtomicJsonFile 原子替换
  path_provider: ^2.1.2

  # 跨端传输：dart:io 内置 HTTP(S)（无 shelf / http 包）
  uuid: ^4.5.1
  basic_utils: 5.8.2             # 自签 TLS 证书生成
  crypto: ^3.0.7
  pointycastle: 4.0.0

  # 二维码配对
  qr_flutter: ^4.1.0
  mobile_scanner: ^7.4.2

  # 歌词/元数据
  charset: ^2.0.1
  audio_metadata_reader: ^1.8.0
  file_picker: 10.3.10           # pin 原因见 pubspec.yaml 注释
  cupertino_icons: ^1.0.8
```

状态管理与代码生成依赖（flutter_bloc、hive_generator、build_runner、permission_handler）均未引入。

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
