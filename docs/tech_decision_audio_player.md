# 技术决策文档：音频播放器与系统媒体会话

## 当前决策

LyricForge 使用分层播放器架构：

- `just_audio`：唯一的底层音频输出引擎；
- `PlaybackSessionService`：唯一的应用级播放队列、当前项、随机、循环和上一首/下一首 Source of Truth；
- `audio_service`：Android/iOS 系统媒体会话桥接，用于后台播放、锁屏/通知栏、耳机/蓝牙按键、Android Auto / CarPlay 等系统控制；
- `audio_session`：配置 music audio session，并与来电/其他音频 App 的系统焦点规则协作。

不要再同时初始化 `just_audio_background`。LyricForge 的队列并不由 `just_audio` 内部 playlist 管理，而由 `PlaybackSessionService` 管理；直接使用 `audio_service` 可以把系统上一首/下一首、Seek、Shuffle 和 Repeat 精确转发到现有应用队列，避免出现两套状态。

## 核心原则

1. **只有一个真实播放器。** `audio_service` 不创建第二个 `AudioPlayer`，只桥接系统控制。
2. **只有一个队列状态。** App 内播放器、锁屏、通知栏和耳机按键都调用同一个 `PlaybackSessionService`。
3. **系统媒体信息来自当前 `PlaybackItem`。** 标题、艺人、封面、时长与当前 queue index 必须跟随应用状态更新。
4. **后台能力只在 Android / iOS 初始化。** Windows 桌面端继续使用现有 in-process 播放路径，不因移动端媒体服务增加启动风险。
5. **播放中断交给系统音频会话。** `just_audio` 默认处理 `audio_session` interruption/focus 事件，不自行实现另一套来电抢占逻辑。

## 依赖

```yaml
dependencies:
  just_audio: ^0.10.5
  audio_service: ^0.18.19
  audio_session: ^0.1.24
```

`pubspec.lock` 必须由真实 `flutter pub get` 生成，不手工伪造。

## Android

需要：

- `WAKE_LOCK`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `AudioService` foreground service
- `MediaButtonReceiver`
- `MainActivity` 继承 `AudioServiceActivity`（或兼容的 AudioService activity 基类）

系统播放通知由 `audio_service` 的 `PlaybackState` 和 `MediaItem` 驱动。

## iOS

`Info.plist` 必须包含：

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

移动端启动时配置 `AudioSessionConfiguration.music()`。

## 系统操作映射

| 系统动作 | LyricForge 动作 |
|---|---|
| Play / Pause | `PlaybackSessionService.togglePlayPause()` |
| Previous | `skipPrevious()` |
| Next | `skipNext()` |
| Seek | `seek()` |
| 选择队列歌曲 | `playAt()` |
| Shuffle | `setShuffleEnabled()` |
| Repeat | `setRepeatMode()` |

系统动作不直接修改 `just_audio` playlist。

## 验证要求

在合并移动后台播放相关改动前，应在真实设备验证：

- Android 锁屏、通知栏、蓝牙耳机播放/暂停/上一首/下一首；
- iOS Control Center、锁屏和耳机按键；
- App 进入后台、熄屏后继续播放；
- 来电/音频焦点中断后行为；
- 系统显示标题、艺人、封面、时长和进度；
- Shuffle / Repeat 从 App 改动后同步到系统，从系统改动后同步回 App；
- 桌面 Windows 启动和播放行为不受影响。
