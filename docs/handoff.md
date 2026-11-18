# Handoff

## 目标

按 UI/UX 审计（`artifacts/ui-audit/`）的路线图实施阶段 1，PR #470（草稿）：

- **B-02**：所有用户可见的旧名 Elysium Player 统一为 LyricForge KTV；决定数据目录的平台标识（Windows `ProductName`/`BINARY_NAME`、macOS `PRODUCT_NAME`）按 D-029 保留。
- **A-01 / A-03 / S-01**：强调色填充上的文字改为黑色（`AppColors.onAccent`，8.1:1）；SnackBar 默认改为中性 `bgHighlight` 白字；`textTertiary` #6A6A6A → #8F8F8F；文本主题不再声明未打包的 Inter。
- **T-01 不实施**：RemoteMediaLibraryScreen 按 2026-11-03 工作日志是有意保留的待装配页面；审计报告已更正（T-01 降为 P3，A-01 对比度复算为 2.59:1）。

合并前先征求用户确认，并在真机上做下方的视觉检查。

## Git 现场

- 分支：`arena/f1dee18e-lyric-forge-ktv`，已变基到 main `028e335`（#471）。#471 也新增了 D-028，本分支的决定改编号为 D-029。
- 用于在 CI 上运行 `dart format` 的临时 workflow 已从历史中删除，不在 PR diff 里。
- 提交（变基后，自底向上）：审计资料 → 改名 → 主题对比度 → 审计更正 → 本文件。

## 已改文件

- 改名：14 个 Dart 文件（UI 文案、诊断名、媒体会话、麦克风权限提示、配对错误）、2 个测试、AndroidManifest、iOS Info.plist、Windows `main.cpp`、Linux `my_application.cc`。
- 主题：`lib/core/theme/color_tokens.dart`、`lib/core/theme/app_theme.dart`。
- 一次性格式化（tall style 旧债）：两个主题文件、`mobile_system_media_session.dart`、`record_soloud_ktv_microphone_service.dart`。
- 文档：`decisions.md`（D-029）、工作日志 `2026-11-18-2100`、`2026-11-18-2110`、审计资料更正、本文件。

## 检查结果

PR #470 全部 8 项检查通过：Flutter Quality Gate（格式、analyze、全量测试、工作日志）、Windows debug 构建与 3 个 Windows 测试、5 个 ASR 契约工作流（定向 analyze + 测试）。沙箱无法下载 CI 日志，所以没有具体的测试数量和 info 数量。

## 下一步

在真机上检查：主按钮、音乐库分区 ChoiceChip、导航指示器、设置里的 Switch（绿底黑字）；成功和失败的 SnackBar；Windows/Linux 窗口标题；Windows 上已有音乐库照常加载。确认后再开始审计路线阶段 2（`lib/core/widgets/` 共享组件）。

## 已知风险

- 视觉变化没有在运行中的应用上看过（沙箱不能运行 Flutter）。
- Windows 文件属性/任务管理器与 macOS 应用包名仍是旧名，需要数据目录迁移后才能改（D-029）。
- 去掉 Inter 后，装了 Inter 的电脑会改用系统默认字体；正式字体留到品牌阶段。

最后更新：2026-11-18 22:30（Asia/Taipei）
