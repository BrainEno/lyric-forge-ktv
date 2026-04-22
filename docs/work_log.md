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
