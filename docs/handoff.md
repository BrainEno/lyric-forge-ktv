# Handoff

## 目标

审计路线阶段 2 的下一轮（PR #473 已合并为 `fb33769`）。这一轮多做几个任务：

1. C-05 共享标签组件 `AppBadge`（`lib/core/widgets/`），先迁移首页、导入、复核收件箱、参考对齐和歌词编辑器的标签。
2. C-05 后半：播放器、播放队列、工程详情和转写队列的标签。

## Git 现场

- 分支：`arena/abbb9c6e-lyric-forge-ktv`，基于 main `fb33769`。
- 提交：`Add a shared badge widget`；`Use shared badges on player and queue screens`。

## 已改文件

见工作日志 `2026-11-19-0941-add-shared-badge-widget.md`（新组件和测试、五个迁移文件）和 `2026-11-19-0955-use-shared-badges-on-player-and-queues.md`（中性底色改为半透明、图标放进文字里、五个迁移文件）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- C-05 已完成。之后：C-07 `TransportBar`、错误/加载状态、C-03 ASR 设置拆卡、其余空状态。

## 已知风险

- 没有在运行中的应用里看过；中性 `LyricTinyBadge` 从灰色底改为表面色底、次级文字色，对比度更高；中性标签用半透明白底，在卡片和页面背景上都可见。转写计数标签矮了 2px。详见工作日志。

最后更新：2026-11-19 09:55（Asia/Taipei）
