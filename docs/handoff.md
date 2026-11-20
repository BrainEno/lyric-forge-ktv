# Handoff

## 目标

审计路线的第十六轮（第十五轮 PR #487 已合并为 `4201251`）。按第十五轮交接的“下一步”做 A-04 剩下的无名点击区域；真机检查在沙箱里做不了，只记录。本轮要求有效代码量不少于 1000 行（lib+test 不计空行、注释和只改缩进的行约 1780 行），PR 过 CI 后直接合并。

1. A-04（D-037）：新共享组件 `core/widgets/app_tap_target.dart`，把可点的卡片或行读成一个按钮：一句话标签、点按提示、禁用 / 当前状态，卡片里的小按钮和菜单项成了自定义操作。用到 14 处：首页的队列预览、最近听过、歌词工程卡；导入页两张卡；校对收件箱的行（“全部标为已复核”是行的操作）；播放页歌词列表和三行聚焦视图；本地曲库的歌手、专辑、迷你专辑、播放列表和歌曲卡；播放队列的行；桌面后台解析条（暂停 / 继续是操作，进度是 value）；手机端桌面曲库的歌曲行和歌手 / 专辑卡（下载状态读进标签，下载是操作）。
2. 措辞放在各功能自己的文件：`dashboard_semantics.dart`、`player_lyric_semantics.dart`、`local_library_semantics.dart`、`playback_queue_semantics.dart`、`remote_library_semantics.dart`；收件箱和解析条用自身的静态方法。都有单元测试。
3. 审计总表状态一节改为“第 16 轮核对”：A-04 改为已处理（代码层面）。审计脚本重扫，`lib` 里 27 处 `InkWell` / `GestureDetector` 都有名字或在有名字的节点里。

## Git 现场

- 分支：`arena/9f174b56-lyric-forge-ktv`，基于 main `4201251`。
- PR #488（squash 合并）。
- 提交：`Read tappable cards and rows as one button`、`Add a temporary format probe`、`Apply format and wrap two if bodies in braces`、`Remove the format probe and update the handoff`。

## 已改文件

见工作日志 `2026-12-03-0930`；新决定 D-037；审计总表状态一节。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑，并用临时探针工作流（合并前删除）。第一次探针：analyze 没有错误和警告，183 条提示（与上轮相同；本轮改到的文件里有两条旧的 `curly_braces_in_flow_control_structures`，已顺手修掉，之后应为 181）；全部测试 3613 个通过、2 个跳过；本轮新增和改动的测试文件共 101 个用例全过，包括播放队列行的“上移 / 下移”与标签在同一节点上；格式有差异。探针每一步最多留 10 条注释，第一次只拿到部分格式补丁，第二次改成只跑格式、轮换 notice/warning/error 取完整补丁，两次补丁都已应用。工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`（0 错误）。

## 下一步

- 在真机上确认（第 14–16 轮都没做）：11 号小字和小号徽章；编辑器的筛选、开始复核、跟随播放和拆分；用 TalkBack / VoiceOver 听一遍编辑器行、全屏 KTV 和本轮的卡片（尤其播放队列行的“上移 / 下移”和标签是否在同一个停顿上）。
- `ai_transcription_settings_cards.dart` 仍有约 565 行，四张卡可以各自成文件，但目前没有维护上的问题。
- `lyric_list_pane.dart` 第 408、438、845 行附近有三条旧 lint 提示，可以顺手清掉。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- 这些卡片改成 `excludeSemantics` 后，卡内文字、徽标和 ⋯ 菜单不再被单独读出；以后用 `find.bySemanticsLabel` 找卡内片段的测试会找不到（D-037）。卡里新加按钮或状态时要同时加进标签或操作，否则读屏用户够不到。
- 播放队列行依赖 Flutter 的合并规则：`container: false` 的标签并入列表加的“上移 / 下移”节点，前提是行上不再有自定义操作；测试固定了这一点。

最后更新：2026-12-03 10:40（Asia/Taipei）
