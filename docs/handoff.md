# Handoff

## 目标

审计路线阶段 2 的下一轮（PR #473 已合并为 `fb33769`）。这一轮多做几个任务：

1. C-05 共享标签组件 `AppBadge`（`lib/core/widgets/`），先迁移首页、导入、复核收件箱、参考对齐和歌词编辑器的标签。
2. C-05 后半：播放器、播放队列、工程详情和转写队列的标签。
3. C-07 共享传输控制 `TransportBar`：正在播放、快速播放、工程播放器和沉浸 KTV。
4. 共享错误状态 `AppErrorState`：歌词编辑器、工程播放器、工程详情、艺人/专辑浏览。
5. 共享加载状态 `AppLoadingState`：复核收件箱、工程播放器、工程详情和三个音乐库界面。

第二轮（同一 PR #474）：

6. C-03 识别设置拆成四张分区卡片，SE-02 去掉重复的“设置”标题。

## Git 现场

- 分支：`arena/abbb9c6e-lyric-forge-ktv`，基于 main `fb33769`。
- 提交：`Add a shared badge widget`；`Use shared badges on player and queue screens`；`Add a shared transport bar for player screens`；`Add a shared error state for failed loads`；`Add a shared loading state for pages and panes`；`Remove the temporary format probe`；`Split the recognition settings into section cards`。

## 已改文件

见工作日志 `2026-11-19-0941-add-shared-badge-widget.md`（新组件和测试、五个迁移文件）和 `2026-11-19-0955-use-shared-badges-on-player-and-queues.md`（中性底色改为半透明、图标放进文字里、五个迁移文件）和 `2026-11-19-1005-add-shared-transport-bar.md`（新组件和测试、四个播放器界面）和 `2026-11-19-1015-add-shared-error-state.md`（新组件和测试、`AppEmptyState.iconColor`、四个迁移文件）和 `2026-11-19-1025-add-shared-loading-state.md`（新组件和测试、六个迁移文件）和 `2026-11-19-1035-split-asr-settings-into-cards.md`（分区卡片、概览组件、设置页）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。第一次提交的格式问题（测试里的 `MaterialApp` 嵌套需要拆行）靠一个临时格式探针工作流定位，已修复，探针已删除。

## 下一步

- C-05、C-07 已完成（全局/移动播放条的紧凑控制暂不迁移）。错误和加载状态已完成。C-03 已完成。之后：A-02 全局播放快捷键、token 清理（S-05/E-06/E-03/S-04）、其余空状态。

## 已知风险

- 没有在运行中的应用里看过；中性标签（含 `LyricTinyBadge`）改为半透明白底、次级文字色，在卡片和页面背景上都可见，对比度更高。转写计数标签矮了 2px。播放按钮尺寸改为跟随布局（手机 56、其它 64），KTV 播放按钮从强调色改为白色。加载失败页统一为红色图标、说明文字和浅色“重试”按钮；三个页面加载时多一行说明文字。识别设置从一张大卡片变成四张分区卡片。详见工作日志。

最后更新：2026-11-19 10:35（Asia/Taipei）
