# [2025-04-22 19:05] 接入 AppTheme 和 AppRouter，完成 Dashboard 产品入口

- Scope: 重写 main.dart 接入暗色主题和路由系统，将 Dashboard 从占位页面升级为真正的产品入口，包含"新建工程"按钮和空状态提示。这是产品首次可运行的骨架，为后续功能开发提供验证基准。
- Files: `lib/main.dart`, `lib/features/home/presentation/screens/dashboard_screen.dart`
- Validation:
  - `flutter analyze` => No issues found
- Notes: Dashboard 采用 Spotify-inspired 设计语言，使用 bgBase 深色背景、accent 绿色主按钮、圆角卡片式空状态。暂未接入真实项目列表数据，Phase 1.2 将添加 Repository 层。
- Commit: `feat: wire up theme and router, build dashboard entry point`
