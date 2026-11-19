# Handoff

## 目标

审计路线的第十五轮（第十四轮 PR #486 已合并为 `84a50ae`）。按第十四轮交接的“下一步”做：C-03 识别设置再拆、A-04 语义标注走查、编辑器工具栏 / 列表 / 右侧检查面板直接接收两个分组；真机检查在沙箱里做不了，只记录。lib+test 代码量按以往要求不少于 800 行（本轮约 +2800 / −620）。

1. C-03：设置 → 本地识别的安装、暂停、识别已有模型、迁移和删除流程移到 `AiTranscriptionSettingsController`（`ai_transcription_settings_controller.dart`，`ChangeNotifier`，只依赖领域服务），有单元测试；`ai_transcription_settings_section.dart` 从约 590 行降到约 240 行，只留需要 `BuildContext` 的对话框、目录选择和提示条。四个源码契约测试同时读取 section、cards 和 controller。
2. E-04 后续：`LyricEditorToolbar`、`LyricListPane`、`InspectorPane` 直接接收 `LyricReviewControls` / `LyricPlaybackControls`，自己算选中行、筛选、“显示全部歌词”、复核开关、播放头所在行和带偏移的跳转；内容组件不再拆包。新测试 `lyric_editor_panes_controls_test.dart`。
3. A-04（D-036）：编辑器每一行对读屏是一个节点，一句话读出行号、时间段、文字和状态，选中是 `selected`，双击 / 右键 / 长按才有的编辑都成了自定义操作（`lyric_row_semantics.dart`）；行内编辑的两个时间、逐字时间小块和全屏 KTV（显示播放控制 / 退出全屏）也有了名字或操作。
4. 审计总表状态一节改为“第 15 轮核对”：C-03 已处理，E-04 补充，A-04 仍为部分。

## Git 现场

- 分支：`arena/5f82c3bf-lyric-forge-ktv`，基于 main `84a50ae`。
- 提交：`Move the recognition settings flows into a controller`、`Give editor rows one spoken label`，以及探针和格式修正的提交（合并时 squash）。

## 已改文件

见工作日志 `2026-12-02-0930`、`2026-12-02-1100` 两条记录；新决定 D-036；审计总表状态一节。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑，并用了临时探针工作流（合并前删除），结果见 PR 描述。工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`（0 错误）。

## 下一步

- A-04 剩下的无名点击区域（审计脚本找出，未处理）：`dashboard_now_playing.dart:449`、`dashboard_shelves.dart:123/220`、`import_audio_screen.dart:361`、`review_inbox_screen.dart:404`、`local_artist_album_browser_screen.dart:776/837`、`local_collections_screen.dart:1131`、`local_library_explorer_screen.dart:971`、`player_screen.dart:735/877`、`global_player_bar.dart:229`、`mobile_global_player_bar.dart:85`、`playback_queue_panel.dart:248`、`global_transcription_queue_bar.dart:57`、`mobile_remote_grouped_library_screen.dart:483`、`mobile_remote_music_library_screen.dart:698`。行号是第 15 轮开始时的位置。
- 在真机上确认（第 14、15 轮都没做）：11 号小字和小号徽章；编辑器的筛选、开始复核、跟随播放和拆分；用 TalkBack / VoiceOver 听一遍编辑器行和全屏 KTV 的自定义操作。
- `ai_transcription_settings_cards.dart` 仍有约 565 行，四张卡可以各自成文件，但目前没有维护上的问题。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- 编辑器行改成 `excludeSemantics` 后，行内徽章和试听按钮不再被单独读出；以后用 `find.bySemanticsLabel` 找行内片段的测试会找不到（D-036）。
- 列表的“显示全部歌词”现在由筛选推出：只要筛选不是“全部”就出现，之前要看调用方是否传入回调。
- 设置控制器在页面关闭后仍可能有下载或迁移在跑；它在每次 await 后检查 `isDisposed`，不会再通知已销毁的监听者，但后台操作本身不会被取消（与拆分前一致）。

最后更新：2026-12-02 11:30（Asia/Taipei）
