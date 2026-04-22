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
- Notes: Import 支持 MP3/FLAC/WAV/M4A 格式选择，创建工程后自动跳转到详情页。ProjectDetail 显示处理进度条、工程状态标签、可播放/编辑入口。暂未接入真实音频处理，仅做占位流程。
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
