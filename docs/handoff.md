# Handoff

## 目标

用户更正：产品名是 **Elysium Player**，不是 LyricForge KTV。PR #470（已合并，`c7c2b1a`）根据 README 和仓库名把界面改成了 LyricForge KTV，方向错了。本分支的工作：

1. 把对外名称恢复为 Elysium Player，并把 README、CONTRIBUTING、`docs/` 现行文档、导出文件的创作工具标记和代码注释一起改成 Elysium Player（D-030，D-029 标记为已取代）。
2. 接着做审计路线阶段 2 的 UI 优化（`lib/core/widgets/` 共享组件等），作为单独的提交和工作日志。

## Git 现场

- 分支：`arena/abb66cea-lyric-forge-ktv`，基于 main `c7c2b1a`。
- 提交：`Restore Elysium Player as the product name`。

## 已改文件

见工作日志 `docs/log/entries/2026-11-18-2300-restore-elysium-player-name.md`：约 45 个 Dart 文件（界面文字、导出标记、注释、测试）、4 个平台文件、README/CONTRIBUTING/问题模板、11 份 `docs/` 页面、`decisions.md`（D-030）、审计资料更正。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地做了：按字符数检查改动行长度，只有 ASS 标题那一行因改名超过 80 列，已经改写；用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- 等 CI 通过后再合并。
- 审计路线阶段 2：`AppArtwork`、`AppBadge`、`AppEmptyState`、`TransportBar` 共享组件，菜单分组校对，ASR 设置拆分。

## 已知风险

- 视觉和文字变化没有在运行中的应用里看过。
- 新导出的 LRC/ASS 文件里，创作工具标记从 LyricForge 改为 Elysium Player；以前导出的文件不受影响。
- 数据目录、协议头、User-Agent 和 TLS 证书字段仍用 LyricForge（D-030），改名需要单独做数据迁移。

最后更新：2026-11-18 23:10（Asia/Taipei）
