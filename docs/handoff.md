# Handoff

## 目标

审计路线的第五轮（PR #476 已合并为 `2fb8680`）。用户取消了每个提交的规模约定，这一轮继续多做几个任务：

1. P-02 工程详情：人声/伴奏导入收进“伴奏与人声”折叠行，行内显示已有哪些音轨。
2. A-04 播放条读屏标注：两个播放条的标题区读作一个按钮“正在播放：歌名，歌手”；加载时播放键读“正在加载”；队列按钮读“播放队列，N 首”并报告展开状态；音乐库搜索的清除按钮补上提示。
3. E-05 窄屏行检查器：底部面板从固定 88% 改为先开到 62%，显示上一行/下一行，可拖动到 40% 或 92%，加关闭按钮并避开键盘。
4. SE-06 设置页宽屏双栏：内容宽 ≥1080 时“AI 识别”在左（3:2），“故障排查”在右，跨断点缩放时保留状态。

## Git 现场

- 分支：`arena/1cf88c2c-lyric-forge-ktv`，基于 main `2fb8680`。
- 提交：`Fold track imports on the project page`；`Label the player bars for screen readers`；`Let the narrow line inspector sheet resize`；`Put settings groups side by side on wide windows`。

## 已改文件

见工作日志 `2026-11-24-1210-fold-track-imports-on-the-project-page.md`（工程详情的伴奏与人声折叠）和 `2026-11-24-1220-label-the-player-bars-for-screen-readers.md`（播放条读屏标注）、`2026-11-24-1240-let-the-narrow-line-inspector-sheet-resize.md`（窄屏行检查器）、`2026-11-24-1300-put-settings-groups-side-by-side-on-wide-windows.md`（设置页双栏）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。注意：CI 在 `flutter pub get` 之后才运行 `dart format`，排查格式问题以 pub get 之后的结果为准。

## 下一步

- 本轮其余任务见 PR 描述。

## 已知风险

- 没有在运行中的应用里看过。详见工作日志。

最后更新：2026-11-24 13:00（Asia/Taipei）
