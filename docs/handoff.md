# Handoff

## 目标

审计路线的第九轮（第八轮 PR #480 已合并为 `7742df3`）。每轮多做几个任务，lib+test 代码量至少 800 行。用户反馈：淡紫按钮上有些部分对比度差；底部的音乐库、收藏、播放列表等点击后没什么反馈。

1. 淡紫按钮前景色：图标按钮主题设了灰色前景，连填充（淡紫）和色调图标按钮也被涂成灰色（灰配淡紫约 1.1:1）；容器色没设，选中的筛选标签是黑字配半透明紫（1.57:1），色调按钮、分段按钮和导航指示器都和主按钮一样亮。现在补齐了容器色：深紫 `#3A2E66` 配浅紫 `#E8DEFF`（9.3:1），描边灰 `#7A7A7A`；主题里的图标按钮不再设前景色。
2. 外壳组件拿不到 Navigator：播放条、转写队列条和导航都在 `MaterialApp.builder` 里，位于 Navigator 旁边而不是下面，直接用 `Navigator.of`、`showDialog` 会报错或拿错上下文。新增 `AppChromeScope`（`pushNamed`、`contextOf`）、`destination_navigation.dart`（再点当前目的地不再重复压页面）和 `lib/app/app_chrome.dart`。桌面端外壳的 `Overlay(initialEntries:)` 只读一次初始项，导航栏一直高亮第一个页面、全屏播放器上播放条也不隐藏；现在只建一次 OverlayEntry 并自己监听路由。移动端外壳原来没有 Overlay，底部导航长按提示会抛 “No Overlay widget found”，现在共用同一个 Overlay 宿主。
3. 播放条上的链接（音乐库、收藏、歌单等）：`PlayerBarDestinationButton` 用深紫底标出当前所在页面，点击时图标弹一下（`AppTapPulse`）并给选择触感；已在该页面时只弹一下，不再重复打开。
4. 导航栏和侧栏：每次点击图标弹一下并给触感，再点当前目的地不再重复压页面；指示器为深紫、选中图标浅紫、选中文字白色加粗。
5. 音乐库分区条：分区图标点击时弹一下并给触感（包括再点当前分区）；内容切换时 220 ms 淡入上移（减少动态效果时直接切换）；从别处打开分区时，窄屏分区条会滚到该分区。
6. 忙碌状态的转圈：按钮里的转圈统一用 `AppButtonSpinner`，跟随按钮图标颜色。填充/色调按钮禁用时为 `#8F8F8F` 配 `#3E3E3E`（3.3:1，原来约 2.2:1）。三个播放圆钮共用 `AppTheme.playDisc`，加载时保持浅灰底黑色转圈（10:1，原来桌面端是透明底 1.1:1，移动端和传输条是 `#535353` 底 2.7:1）。首页播放按钮缓冲时保持淡紫底黑色转圈。
7. 收藏爱心：点击后立即填充（淡紫）或清空，填充时弹一下并给触感，写入失败再恢复并提示；不再在每次写入时变灰。

## Git 现场

- 分支：`arena/595833ba-lyric-forge-ktv`，基于 main `7742df3`，PR #481。
- 提交：`Give lavender buttons readable foregrounds`、`Let the app chrome reach the navigator`、`Show where the player bar links lead`、`Make navigation presses visible`、`Answer library section presses`、`Keep busy spinners visible`、`Answer the favourite heart at once`、`Remove the format probe and update the handoff`。

## 已改文件

见工作日志 `2026-11-26-1030` 至 `2026-11-26-1130` 的七条记录。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑。本轮同样用了临时探针工作流（合并前已删除）。靠它修掉了：几处格式问题，移动端外壳缺 Overlay 导致的三个测试失败（也是真实的崩溃），以及三个脉冲测试少等了一帧（点击后的那一帧才开始计时）。最后一次探针：3207 个测试全部通过，analyze 仍是基线的 186 条提示。行长度在本地按字符数检查过；工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- 剩余审计项：沉浸式 KTV 控件，T-02/T-03（传输子域体量），B-02 的文档残留（迁移弹窗里的 “LyricForge ASRRuntime” 是不是真实的目录名，需要确认）。
- 在真机上确认触感和弹跳的力度是否合适（`AppTapPulse.defaultPeakScale` 为 1.18，分区和爱心为 1.3–1.35）。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- 移动端外壳现在也包在 Overlay 里；`test/widget_test.dart` 原来专门断言移动端没有 Overlay（原因没有记录），已改为断言有外壳 Overlay。如果移动端出现输入法或焦点问题，先查这里。
- 收藏爱心改为乐观更新；如果存储很慢，连续点击在写入完成前会被忽略。

最后更新：2026-11-26 11:40（Asia/Taipei）
