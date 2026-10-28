# [2025-04-23 22:45] Phase 1.5: 实现快速播放模式

- Scope: 不创建工程直接播放音频，并保存播放历史。包含：1) Dashboard 添加"快速播放"按钮；2) 创建 QuickPlayScreen 简化版播放器；3) 创建 PlayHistory 模型和存储；4) Dashboard 显示最近播放历史。
- Files: `lib/core/navigation/app_router.dart` (添加 quickPlay 路由), `lib/features/home/presentation/screens/dashboard_screen.dart` (添加快速播放按钮和历史列表), `lib/features/player/presentation/screens/quick_play_screen.dart` (新建), `lib/features/player/domain/models/play_history.dart` (新建), `lib/features/player/domain/repositories/play_history_repository.dart` (新建), `lib/features/player/data/repositories/memory_play_history_repository.dart` (新建), `lib/core/services/service_locator.dart` (注册 playHistoryRepository), `pubspec.yaml` (添加 uuid 依赖)
- Validation:
  - `flutter analyze` => No issues found
  - `flutter pub get` => Got dependencies
- Notes: QuickPlayScreen 支持直接选择音频文件播放，无需创建工程。播放完成后自动保存到历史记录。Dashboard 显示最近 5 条播放历史，点击可快速重新播放。PlayHistory 模型包含文件名、路径、播放时间、最后播放位置等信息。UI 保持 Spotify 风格，播放历史使用播放图标区分于工程项目。
- Commit: `feat: add quick play mode with play history`
