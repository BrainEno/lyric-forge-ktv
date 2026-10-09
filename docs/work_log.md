# Work Log

### [2025-04-22 19:05] 接入 AppTheme 和 AppRouter，完成 Dashboard 产品入口

- Scope: 重写 main.dart 接入暗色主题和路由系统，将 Dashboard 从占位页面升级为真正的产品入口，包含"新建工程"按钮和空状态提示。这是产品首次可运行的骨架，为后续功能开发提供验证基准。
- Files: `lib/main.dart`, `lib/features/home/presentation/screens/dashboard_screen.dart`
- Validation:
  - `flutter analyze` => No issues found
- Notes: Dashboard 采用 Spotify-inspired 设计语言，使用 bgBase 深色背景、accent 绿色主按钮、圆角卡片式空状态。暂未接入真实项目列表数据，Phase 1.2 将添加 Repository 层。
- Commit: `feat: wire up theme and router, build dashboard entry point`

### [2025-04-22 19:15] 添加 ProjectRepository 抽象与内存实现

- Scope: 定义 ProjectRepository 领域接口，实现内存版存储（MemoryProjectRepository），Dashboard 接入真实项目列表数据流。建立 ServiceLocator 简单依赖注入，为后续替换持久化存储预留扩展点。
- Files: `lib/features/project/domain/repositories/project_repository.dart`, `lib/features/project/data/repositories/memory_project_repository.dart`, `lib/core/services/service_locator.dart`, `lib/features/home/presentation/screens/dashboard_screen.dart`, `lib/main.dart`
- Validation:
  - `flutter analyze` => No issues found
- Notes: Repository 遵循 AGENTS.md 架构规则：接口在 domain/，实现在 data/。Dashboard 使用 FutureBuilder + RefreshIndicator 实现异步数据加载与下拉刷新。内存存储会在应用重启后丢失数据，Phase 2 可替换为 Drift/Hive。
- Commit: `feat: add project repository with memory implementation`

### [2025-04-22 19:25] 完成导入流程占位与 ProjectDetail 详情页

- Scope: 实现 ImportAudioScreen 文件选择、工程创建流程；ProjectDetailScreen 展示工程详情、处理进度、状态管理。添加 file_picker 和 path_provider 依赖，Dashboard → Import → ProjectDetail 流程已贯通。
- Files: `lib/features/import/presentation/screens/import_audio_screen.dart`, `lib/features/project/presentation/screens/project_detail_screen.dart`, `pubspec.yaml`
- Validation:
  - `flutter analyze` => No issues found
  - `flutter pub get` => Got dependencies
- Notes: Import 支持 MP3/FLAC/WAV/M4A 格式选择，创建工程后自动跳转到详情页。ProjectDetail 显示工程详情、处理进度、工程状态标签、可播放/编辑入口。暂未接入真实音频处理，仅做占位流程。
- Commit: `feat: add import flow and project detail screen`

### [2025-04-22 20:00] 实现 LyricEditor 歌词编辑器与 Player 播放器

- Scope: 完成 LyricEditorScreen 手动歌词编辑功能（添加/删除/修改歌词行、时间戳调整、副歌标记、全局偏移调节）和 PlayerScreen 播放器骨架（进度条控制、播放/暂停、歌词同步高亮、点击歌词跳转）。形成"编辑→预览"闭环。
- Files: `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/player/presentation/screens/player_screen.dart`
- Validation:
  - `flutter analyze` => No issues found
- Notes: LyricEditor 支持行级时间戳编辑（+/-0.1s/1s）、副歌高亮显示、空行添加。Player 使用 Timer 模拟播放进度，歌词自动高亮当前行。均为占位实现，未接入真实音频播放。
- Commit: `feat: add lyric editor and player with synced lyrics`

### [2025-04-22 21:30] Phase 1.3 Task 1-5: 接入 just_audio 音频播放基础设施

- Scope: 添加 just_audio 依赖并构建完整的音频播放服务层，为 Phase 1.3 PlayerScreen 重构提供基础。包含：1) 添加 just_audio/audio_session 依赖；2) 扩展 AudioAsset 添加 AudioSourceType 枚举和扩展方法；3) 创建 PlaybackState 播放状态模型；4) 定义 AudioPlayerService 领域接口；5) 实现 JustAudioPlayerService 适配器；6) 注册到 ServiceLocator。
- Files: `pubspec.yaml`, `lib/features/project/domain/models/audio_asset.dart`, `lib/features/player/domain/models/playback_state.dart` (新建), `lib/features/player/domain/services/audio_player_service.dart` (新建), `lib/features/player/data/services/just_audio_player_service.dart` (新建), `lib/core/services/service_locator.dart`
- Validation:
  - `flutter analyze` => No issues found
  - `flutter pub get` => Got dependencies
- Notes: 完整实现音频播放服务抽象，支持原声/伴奏/人声三种音源切换。JustAudioPlayerService 包装 just_audio 库，提供统一的 PlaybackState 状态流。AudioAsset 新增扩展方法简化音源选择和可用性检查。目前仅为基础设施，PlayerScreen 重构将在 Task 6 完成。
- Commit: `feat: add just_audio playback service layer with source switching`

### [2025-04-22 22:30] Phase 1.3 Task 6: 重构 PlayerScreen 接入真实音频播放

- Scope: 将 PlayerScreen 从 Timer 模拟播放重构为使用 just_audio 的真实音频播放器。包含：1) 接入 AudioPlayerService 服务；2) 从音频文件获取真实时长和进度；3) 添加音源切换 UI（原声/伴奏/人声按钮）；4) 实现带缓冲显示的进度条；5) 歌词同步从真实播放位置获取；6) 添加加载和缓冲状态视觉反馈。
- Files: `lib/features/player/presentation/screens/player_screen.dart` (重写), `lib/core/services/service_locator.dart` (添加 audioPlayerService)
- Validation:
  - `flutter analyze` => No issues found
- Notes: PlayerScreen 现在支持播放真实的 MP3/FLAC/WAV/M4A 文件。新增 _ProgressBar 组件显示缓冲进度和播放进度，_AudioSourceSelector 组件支持切换音源（仅显示可用音源），_PlaybackControls 显示缓冲加载动画。UI 保持 Spotify 风格暗色主题。Phase 1.3 全部完成，播放器已可正常使用。
- Commit: `feat: refactor PlayerScreen with real audio playback and source switching`

### [2025-04-23 22:45] Phase 1.5: 实现快速播放模式

- Scope: 不创建工程直接播放音频，并保存播放历史。包含：1) Dashboard 添加"快速播放"按钮；2) 创建 QuickPlayScreen 简化版播放器；3) 创建 PlayHistory 模型和存储；4) Dashboard 显示最近播放历史。
- Files: `lib/core/navigation/app_router.dart` (添加 quickPlay 路由), `lib/features/home/presentation/screens/dashboard_screen.dart` (添加快速播放按钮和历史列表), `lib/features/player/presentation/screens/quick_play_screen.dart` (新建), `lib/features/player/domain/models/play_history.dart` (新建), `lib/features/player/domain/repositories/play_history_repository.dart` (新建), `lib/features/player/data/repositories/memory_play_history_repository.dart` (新建), `lib/core/services/service_locator.dart` (注册 playHistoryRepository), `pubspec.yaml` (添加 uuid 依赖)
- Validation:
  - `flutter analyze` => No issues found
  - `flutter pub get` => Got dependencies
- Notes: QuickPlayScreen 支持直接选择音频文件播放，无需创建工程。播放完成后自动保存到历史记录。Dashboard 显示最近 5 条播放历史，点击可快速重新播放。PlayHistory 模型包含文件名、路径、播放时间、最后播放位置等信息。UI 保持 Spotify 风格，播放历史使用播放图标区分于工程项目。
- Commit: `feat: add quick play mode with play history`

### [2026-10-09 11:46] 打通歌词时间轴校对与 LRC 导出切片

- Scope: 将 ASR 识别结果明确标记为可编辑的 `lyricforge-timeline-v1` 草稿；在歌词校对页增加跟随播放滚动、使用当前播放位置校准选中行起止时间、保留逐行文本纠错与微调，并新增 UTF-8 LRC 导出能力。
- Files: `lib/features/transcription/data/services/local_project_transcription_workflow.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/lyrics/domain/services/lyric_file_export_service.dart`, `lib/features/lyrics/data/services/local_lyric_file_export_service.dart`, `lib/core/services/service_locator.dart`, `test/local_lyric_file_export_service_test.dart`, `docs/lyric-export-format.md`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 用户导出格式固定为 UTF-8 LRC，使用 `[mm:ss.SSS]` 行起点与独立 `[offset:<ms>]`；工程 manifest 继续保存精确结束时间、置信度、副歌和复核元数据。导出测试覆盖毫秒时间戳、offset、空行过滤以及 LRC 导出后重新导入的 round-trip。
- Commit: `Add synced lyric timeline editing and LRC export`

### [2026-10-09 11:52] 让普通同步歌词随播放自动滚动

- Scope: 将普通播放器同步歌词列表改为带 `ScrollController` 的跟播视图；当前歌词行变化或 seek 后平滑滚动到视口上中部，KTV 焦点模式及播放器状态机保持不变。
- Files: `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 当前滚动使用估算行高定位，目标是稳定保证当前行回到可视区；长歌词行可能不是严格像素居中，但不会改变时间轴或 seek 语义。
- Commit: `Auto-scroll synced lyrics with playback`

### [2026-10-09 11:57] 让播放器返回校对后立即读取最新歌词

- Scope: 播放器进入歌词校对器时等待编辑路由返回；用户保存并退出后重新读取当前工程 manifest，使纠正后的歌词文本、时间轴和全局 offset 立即成为当前播放器的同步歌词来源，同时保留现有音频播放会话与播放位置。
- Files: `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 修复了播放器长期持有进入编辑器前 `ProjectManifest` 快照的问题；刷新仅重新读取工程数据，不重新创建或重启当前播放会话。
- Commit: `Refresh player lyrics after timeline editing`

### [2026-10-09 12:03] 固定 LRC 导出的有效播放时间语义

- Scope: 导出 LRC 时把工程 `globalOffset` 烘焙到每行时间戳，避免不同播放器对 `[offset]` 正负方向解释不一致；工程内仍保留独立 offset 供编辑。
- Files: `lib/features/lyrics/data/services/local_lyric_file_export_service.dart`, `test/local_lyric_file_export_service_test.dart`, `docs/lyric-export-format.md`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 用户导出的 LRC 是最终播放时间轴；重新导入后播放对齐保持一致，但 offset 分解会被压平。LyricForge project manifest 继续作为无损编辑主文件；负的最终时间戳会钳制到 `00:00.000`。
- Commit: `Export LRC with effective playback timestamps`

### [2026-10-09 12:14] 增加播放器麦克风 KTV 入口与伴唱模式

- Scope: 在已有同步歌词的播放器顶部增加麦克风 KTV 入口；进入前让用户选择“原唱伴唱”或“纯伴奏”，选择后切换音源并直接进入全屏 KTV。全屏 KTV 中继续允许在这两种演唱音轨之间切换，隔离人声轨不作为 KTV 背景音源暴露。
- Files: `lib/features/player/domain/models/ktv_backing_mode.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `test/features/player/ktv_backing_mode_test.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: “原唱伴唱”映射现有 original mix，“纯伴奏”映射 instrumental stem；底层 `switchSource` 会保留当前播放位置和播放状态。没有 instrumental 时纯伴奏选项明确禁用并提示先生成伴奏轨。
- Commit: `Add microphone KTV entry and backing choice`

### [2026-10-09 12:36] 接入 KTV 实时麦克风监听、独立音量与延迟控制

- Scope: 为全屏 KTV 增加真实麦克风输入和低延迟监听；麦克风 PCM16 由 `record` 捕获，经可测试的增益/延迟 DSP 后送入 `flutter_soloud` 输出。新增麦克风开关、电平表、0–200% 麦克风增益、独立歌曲音量和 0–250ms 监听附加延迟控制；退出全屏 KTV 自动关闭监听。
- Files: `lib/features/player/domain/models/ktv_microphone_state.dart`, `lib/features/player/domain/services/ktv_microphone_service.dart`, `lib/features/player/data/services/pcm_delay_line.dart`, `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/player/data/services/just_audio_player_service.dart`, `lib/core/services/service_locator.dart`, Android/iOS/macOS 麦克风权限配置、Flutter generated plugin registrants, `pubspec.yaml`, `pubspec.lock`, `test/features/player/ktv_microphone_signal_test.dart`
- Validation:
  - `flutter pub get` => success with existing `mobile_scanner`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test test/features/player/ktv_microphone_signal_test.dart` => success
  - `flutter test` => success
  - `flutter build windows --debug` => success
  - `flutter build macos --debug` => success
- Notes: 早期评估的 `audio_io >=0.3` 与现有 `mobile_scanner 7.4.x` 在 `web` 依赖上不可共存，因此改用 `record 6.2.1 + flutter_soloud 5.1.2`，不降级扫码功能。当前“延迟补偿”只允许增加监听延迟，不伪装成能消除硬件已有延迟；UI 会展示 SoLoud 报告的输出延迟（可用时）。本切片不把仅麦克风录制冒充完整 KTV 成品录音，混合录音留给后续共享混音/离线合成链路。
- Commit: `Add low-latency KTV microphone monitoring`

### [2026-10-09 12:58] 打通 KTV 人声录音、对齐保护与离线混音导出

- Scope: 全屏 KTV 增加 take 录音按钮；保存 48kHz/16-bit mono 原始人声 WAV stem 与 session manifest，记录伴唱音源、起始播放位置和音量。录音期间锁定 seek、暂停、切歌和切换音源，并监控外部播放跳变；对齐失效时保留 stem 但阻止错误自动混音。停止后允许重新调节人声/伴奏导出音量，并通过 FFmpeg 生成 WAV 成品。
- Files: `lib/core/services/service_locator.dart`, `lib/features/player/domain/models/ktv_recording_session.dart`, `lib/features/player/domain/services/ktv_recording_service.dart`, `lib/features/player/domain/services/ktv_microphone_service.dart`, `lib/features/player/data/services/local_ktv_recording_service.dart`, `lib/features/player/data/services/pcm16_wav_writer.dart`, `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `test/features/player/ktv_recording_export_test.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` on the repository's original analyzer config => success
  - focused KTV recording + microphone tests => success
  - full `flutter test` => success
  - `flutter build windows --debug` => success
  - `flutter build macos --debug` => success
- Notes: 人声 stem 在监听增益和监听延迟处理之前保存，因此演唱时的监听设置不会破坏性写入录音。若录音中时间轴被暂停、seek、切歌或切换音源破坏，session 会标记对齐不可靠并禁止自动混音，但原始人声仍保留。尚未在真实 Windows/macOS 麦克风设备上完成实际歌曲的听感、声学延迟和啸叫 E2E 验证。
- Commit: `Add aligned KTV take recording and mix export`

### [2026-10-09 14:59] 增加 KTV 麦克风输入设备枚举与热切换底层

- Scope: 在现有 KTV 麦克风服务中增加输入设备枚举、稳定 ID 选择、系统默认回退与监听中热切换能力；`record.InputDevice` 仅保留在 data 层，domain 状态只暴露可序列化的设备 ID、名称和采样率信息。应用服务初始化时会预加载设备列表，后续 UI 可以直接绑定同一状态流。
- Files: `lib/core/services/service_locator.dart`, `lib/features/player/domain/models/ktv_microphone_state.dart`, `lib/features/player/domain/services/ktv_microphone_service.dart`, `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `test/features/player/ktv_microphone_signal_test.dart`
- Validation:
  - `flutter pub get` in existing PR check => success
  - `flutter analyze lib/core/services/service_locator.dart ...` in existing PR check => success
  - `flutter test test/features/transcription/resilient_asr_runtime_manager_test.dart` regression check => success
- Notes: 新增的 player focused tests 已写入 `ktv_microphone_signal_test.dart`，但当前仓库的 path-scoped PR workflow 不会自动执行 player tests，因此本切片没有声称 focused player test 已在 CI 中跑过。物理麦克风设备枚举/拔插/热切换仍需 Windows/macOS 真机验证；下一切片只需把现有 KTV 麦克风面板绑定到这些服务 API，并在 take 录音中禁用设备切换。
- Commit: `Add KTV microphone input device switching`

### [2026-10-09 15:08] KTV 麦克风设备选择接入控制面板

- Scope: 将麦克风输入设备发现/热切换能力接入全屏 KTV 的“麦克风与演唱音量”面板；用户可在“系统默认”和检测到的具体麦克风之间选择并手动刷新。录音 take、麦克风启动或设备刷新期间会锁定设备操作，避免中途换输入源破坏录音一致性；同时修正 `record 6.2.1` 输入设备适配器误读不存在的采样率属性。
- Files: `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `docs/work_log.md`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test test/features/player/ktv_microphone_signal_test.dart` => success
  - `flutter test` => success
- Notes: `record 6.2.1` 当前只提供输入设备 ID/名称，适配器因此保留领域模型的采样率扩展位但不虚构数据，UI 只显示真实设备名称。设备选择仍只保存于当前应用会话，持久化留给后续独立切片；真实 Windows/macOS 多麦克风拔插、蓝牙/USB 切换仍需物理设备 E2E 验证。
- Commit: `Expose KTV microphone device picker`
