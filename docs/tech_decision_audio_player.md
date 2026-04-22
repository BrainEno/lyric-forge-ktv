# 技术决策文档：音频播放器选型

## 候选方案对比

| 维度 | just_audio | audioplayers |
|------|------------|--------------|
| **版本** | 0.10.5 (7个月前) | 6.6.0 (51天前) |
| **下载量** | 704k | 673k |
| **点赞数** | 4.12k | 3.41k |
| **维护状态** | 活跃 (Flutter Favorite) | 活跃 |
| **平台支持** | Android/iOS/macOS/Web/Windows/Linux* | Android/iOS/Linux/macOS/Web/Windows |
| **核心定位** | 功能丰富的专业播放器 | 多实例同时播放 |

*注：Windows/Linux 需要额外插件

## 功能对比

### just_audio 优势
- ✅ **完整的播放列表支持** - ConcatenatingAudioSource, gapless playback
- ✅ **音频剪辑** - 支持播放片段 (setClip)
- ✅ **高级状态管理** - playing + processingState 正交状态模型
- ✅ **缓存支持** - LockCachingAudioSource 边下边播
- ✅ **流媒体支持** - StreamAudioSource 自定义字节流
- ✅ **背景播放** - just_audio_background 插件
- ✅ **均衡器/音效** - 有社区支持
- ✅ **更详细的错误处理** - PlayerException, PlayerInterruptedException

### audioplayers 优势
- ✅ **多播放器实例** - 天生支持同时播放多个音频
- ✅ **更简单的 API** - 适合快速集成
- ✅ **Windows/Linux 原生支持** - 无需额外插件
- ✅ **更新的版本** - 6.6.0 比 just_audio 更新

## 本项目需求匹配度分析

### 需求清单

| 需求 | just_audio | audioplayers | 说明 |
|------|------------|--------------|------|
| 播放本地音频文件 | ✅ | ✅ | 都支持 |
| 播放列表/下一首 | ✅ 原生 | ⚠️ 需自行管理 | just_audio 更完整 |
| 音频源切换（原声/伴奏/人声） | ✅ | ✅ | 都可以 |
| 进度条拖动/Seek | ✅ | ✅ | 都支持 |
| 速度调节 | ✅ | ✅ | 都支持 |
| 音量调节 | ✅ | ✅ | 都支持 |
| 背景播放 | ✅ 官方 | ⚠️ 第三方 | just_audio 更好 |
| 状态流监听 | ✅ 详细 | ✅ 基础 | just_audio 更完整 |
| 错误处理 | ✅ 详细 | ⚠️ 基础 | just_audio 更好 |
| 缓存管理 | ✅ 内置 | ❌ 无 | KTV 需要 |

## 关键决策因素

### 1. KTV 场景的特殊需求
- **需要精确控制** - 歌词同步要求毫秒级精度
- **需要丰富状态流** - 播放状态、缓冲状态、位置流都需要
- **需要背景播放** - 用户锁屏后仍需播放
- **可能多音轨切换** - 原声/伴奏/人声切换

### 2. 跨端一致性
- just_audio: 所有平台统一 API，Windows/Linux 需要额外依赖
- audioplayers: 原生支持所有平台，但功能在各平台有差异

### 3. 社区与生态
- just_audio: Flutter Favorite，更详细的文档和教程
- audioplayers: 社区活跃，版本更新频繁

## 推荐方案

### 🎯 选用：just_audio

**理由**：
1. **KTV 场景的专业性** - just_audio 提供更完整的播放控制、状态流、背景播放支持
2. **生态完整性** - just_audio_background 提供官方背景播放方案
3. **状态管理清晰** - playing + processingState 模型适合复杂的播放器 UI
4. **缓存支持** - LockCachingAudioSource 对未来支持大文件/流媒体友好
5. **错误处理** - 更详细的异常类型有助于调试和用户体验

**Windows/Linux 方案**：
- 使用 just_audio_media_kit 或 just_audio_windows/just_audio_libwinmedia
- 添加依赖：`just_audio_media_kit` + `media_kit_libs_windows_audio` / `media_kit_libs_linux`

## 依赖配置

```yaml
dependencies:
  # 核心音频播放
  just_audio: ^0.10.5
  
  # 背景播放（锁屏控制）
  just_audio_background: ^0.0.1-beta.15
  
  # 音频会话管理（与其他音频应用共存）
  audio_session: ^0.1.24
  
dependencies:
  # Windows 支持
  just_audio_media_kit: ^0.0.1
  media_kit_libs_windows_audio: ^1.0.9
  
  # Linux 支持
  media_kit_libs_linux: ^1.0.9
```

## 备选方案

如果在实现过程中遇到平台兼容性问题，可以回退到 **audioplayers** + **audio_service** 组合，但需要做更多自定义封装。

## 下一步行动

1. 添加 `just_audio` 和相关依赖到 pubspec.yaml
2. 创建 `AudioPlayerService` 领域接口
3. 实现 `JustAudioPlayerService` 适配器
4. 集成 `just_audio_background` 支持锁屏播放控制
