# Handoff

## 目标

审计路线阶段 2 的下一轮（PR #472 已合并为 `ca78297`）：

1. C-04 共享封面组件：`AppArtwork`（`lib/core/widgets/`）和播放器用的 `PlaybackArtwork`，先迁移播放器的四个界面：桌面播放条、移动播放条、播放队列、正在播放。
2. 接着迁移音乐库和首页的五个封面（C-04 后半）。

## Git 现场

- 分支：`arena/96221899-lyric-forge-ktv`，基于 main `ca78297`。
- 提交：`Add a shared artwork widget for player surfaces`；`Use the shared artwork widget on library screens`。

## 已改文件

见工作日志 `2026-11-18-2338-add-shared-artwork-widget.md`（两个新组件、四个播放器文件、两个测试）和 `2026-11-18-2340-use-shared-artwork-in-library.md`（五个音乐库/首页文件、`AppArtwork` 增加 `placeholderColor`）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- C-04 已完成（传输域的 `RemoteMediaArtwork` 因为要走带认证的下载，保持独立）。之后：C-05 `AppBadge`、C-07 `TransportBar`、C-03 ASR 设置拆卡、其余空状态。

## 已知风险

- 没有在运行中的应用里看过；占位图标的大小和颜色有小变化，首页封面占位从渐变改为纯色，详见工作日志。
- 带 `remoteArtworkUri` 的本地条目不再加载远程封面（正常数据里不会出现）。

最后更新：2026-11-18 23:42（Asia/Taipei）
