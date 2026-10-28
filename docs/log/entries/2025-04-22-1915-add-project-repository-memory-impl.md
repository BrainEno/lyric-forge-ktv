# [2025-04-22 19:15] 添加 ProjectRepository 抽象与内存实现

- Scope: 定义 ProjectRepository 领域接口，实现内存版存储（MemoryProjectRepository），Dashboard 接入真实项目列表数据流。建立 ServiceLocator 简单依赖注入，为后续替换持久化存储预留扩展点。
- Files: `lib/features/project/domain/repositories/project_repository.dart`, `lib/features/project/data/repositories/memory_project_repository.dart`, `lib/core/services/service_locator.dart`, `lib/features/home/presentation/screens/dashboard_screen.dart`, `lib/main.dart`
- Validation:
  - `flutter analyze` => No issues found
- Notes: Repository 遵循 AGENTS.md 架构规则：接口在 domain/，实现在 data/。Dashboard 使用 FutureBuilder + RefreshIndicator 实现异步数据加载与下拉刷新。内存存储会在应用重启后丢失数据，Phase 2 可替换为 Drift/Hive。
- Commit: `feat: add project repository with memory implementation`
