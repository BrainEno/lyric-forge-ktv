# Handoff

## 目标

审计路线的第六轮（PR #477 已合并为 `aa71744`）。每轮多做几个任务，lib+test 代码量至少 800 行：

1. N-01 播放入口拆分意图：`PlaybackDestination` 统一规则；首页“打开音乐/选择音乐”去音乐库，最近播放恢复到本地播放器，正在播放卡片按歌曲类型打开对应播放器；`/quick-play` 深链用同一规则。
2. L-02 传输入口：`TransferEntry` 统一名称“跨设备传输”、图标和路由；首页头部去掉桌面端“远程音乐库”按钮，改为“更多”菜单第一项（手机也有）；两个传输页标题统一。

## Git 现场

- 分支：`arena/5b49c7af-lyric-forge-ktv`，基于 main `aa71744`。
- 提交：`Give each player entry its own route`；`Give device transfer one name and two entries`。

## 已改文件

见工作日志 `2026-11-25-1000-give-each-player-entry-its-own-route.md`（播放入口拆分）、`2026-11-25-1020-give-device-transfer-one-name-and-two-entries.md`（传输入口）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。注意：CI 在 `flutter pub get` 之后才运行 `dart format`，排查格式问题以 pub get 之后的结果为准。

## 下一步

- 本轮其余任务见 PR 描述。

## 已知风险

- 没有在运行中的应用里看过。详见工作日志。

最后更新：2026-11-25 10:20（Asia/Taipei）
