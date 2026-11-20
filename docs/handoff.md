# Handoff

## 目标

审计路线的第二十轮（第十九轮 PR #491 已合并为 `2be2b4c`）。本轮按用户选的方向改手机端：风格是“黑胶唱片 · 温暖复古”，以播放器为主，范围是核心听歌路径。要求有效代码量不少于 1000 行，PR 过 CI 后直接合并。

1. 手机端四个去向（D-041）：
   - 「听歌」「音乐库」「歌词」「设置」（`core/navigation/mobile_destinations.dart`）。「歌词」把原来的「工程」「校对」合在一起。
   - 点「听歌」时退回根路由，点其他三个时压在根路由上面，所以按一次返回就回到听歌。
   - 桌面端的侧边栏不变。
2. 听歌首页 `ListenHomeScreen`（手机端的 `/`）：
   - 转动的黑胶、标题、进度条和上一首 / 播放 / 下一首，背景是封面模糊后的颜色；
   - 「播放全部」「随机播放」；
   - 没有歌词时提示导入；
   - 最近播放；
   - 五个音乐库分区的快捷入口。
   - 首页不显示迷你播放条。
3. 「歌词」页：在校对收件箱顶部加“导入并识别”“全部工程”和导入 LRC 的说明（`lyricsHub`）。
4. 共享歌曲行 `AppSongRow`：
   - 音乐库的歌曲、艺人、专辑、收藏、播放列表，以及手机端电脑曲库和下载管理，七个列表都改用它；
   - 正在播放的一行用黄铜色，封面上有节奏条；
   - `NowPlayingListener` 只在歌曲或播放状态变化时重建，不再随进度刷新。
5. 黑胶暖色：
   - `AppColors.vinyl*`；
   - `AppVinylDisc`、`AppRhythmBars`、`AppCoverGlow`；
   - `AppTheme.vinylPlayDisc` 和 `vinylFilled`；
   - 迷你播放条换成暖色渐变、小黑胶封面和黄铜色的进度条和播放键。
   - 循环动画由 `AppMotion` 控制：系统要求减少动态效果时和测试里都不播放。
6. 音乐库在手机宽度下默认用列表。
7. 审计表状态一节改为“第 20 轮核对”，T-03 补了本轮记录。

## Git 现场

- 分支：`arena/c532bb2c-lyric-forge-ktv`，基于 main `2be2b4c`。
- PR #492（squash 合并）。
- 提交：`Make the phone app listening-first with a vinyl home and one song row`、`Add a temporary probe`、`Apply format, regenerate the work log, deliver stream events in the listener test`、`Format after resolving packages in the probe`、`Apply format with the resolved language version`、`Remove the probe`。

## 已改文件

见工作日志 `2026-12-07-0930`、新决定 D-041，以及审计表状态一节。

## 检查结果

沙箱里没有 Dart/Flutter，所以格式、analyze 和测试都在 PR #492 的 CI 上跑，另外用一个临时探针工作流（合并前已删除）。探针结果：
- 第一次：
  - 新测试里只有一个失败：`NowPlayingListener` 的播放 / 暂停测试。流事件在 `pump` 检查完要不要画帧之后才到，所以重建要等下一帧。测试已改成连续 pump 两次。
  - analyze 只有一条提示（测试里用了已弃用的 `pipelineOwner`），已改用 `SemanticsNode.owner`。
  - work log 的生成文件和格式差异补丁已应用。
- 第二次：
  - 质量门的格式检查仍然失败。原因是探针在 `flutter pub get` 之前跑 `dart format`，用的语言版本不同，生成的格式补丁和质量门不一致。探针改成先解析依赖再格式化，按新补丁重新格式化了 7 个文件。
- 第三次：
  - 测试全部 4007 个通过、2 个跳过，比上轮多 121 个。
  - 改动的文件 analyze 没有问题。
  - 格式没有差异，质量门通过。

- 新增六个测试文件：
  - 配色对比度；
  - 黑胶和动画；
  - 歌曲行；
  - 手机端去向；
  - `NowPlayingListener`；
  - 听歌首页。
- 更新了外壳、底部导航和装配契约三个测试。
- 歌曲行和黑胶组件在 `core/widgets`，展示层导入基线不变。

## 下一步

- 真机验证（第 14–20 轮都没做）：
  - 本轮：唱片转动和暂停、封面模糊、暖色在 OLED 屏上的效果、迷你播放条，以及 320 / 390 宽和大字号下的首页；
  - 用 TalkBack / VoiceOver 听一遍新歌曲行、首页唱片和底部导航；
  - 第 17–19 轮留下的网格、准备对话框和编辑器列表。
- 正在播放的页面（`NowPlayingScreen`）还是原来的样式，可以改成同一套黑胶风格。
- 桌面端是否也用暖色，还要用户决定。
- 可选：`ai_transcription_settings_cards.dart` 约 565 行。有四个契约测试读这个路径，导入基线也不能增加。

## 已知风险

- 没有在运行中的应用里看过。
- 手机端启动页从工程首页改成了听歌首页。习惯从首页进工程的用户，现在要从「歌词」→「全部工程」进入。
- 首页的最近播放只在歌曲变化和下拉刷新时重新读取。播放记录保存得比歌曲切换晚时，可能要等下一次切换才显示。
- 模糊背景用 `ImageFiltered`（sigma 48），在低端手机上可能耗电。如果有问题，可以换成预先缩小的封面。

最后更新：2026-12-07 09:30（Asia/Taipei）
