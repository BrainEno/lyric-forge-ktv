# Handoff

## 目标

让真实逐字时间（`LyricLine.words`）有更多来源、更不容易丢失，并且在检查器里可以直接使用：

- 「校对」菜单新增“逐字打轴（卡拉 OK）”：播放歌曲，每唱到一个字（英文按单词）按一次空格，整行按完的行写入真实逐字时间，用于逐字 LRC 和 ASS 导出。
- Whisper 转写读取 token 的 `offsets`，生成逐词时间；无法可靠分组的段整段不写。
- 识别循环删减后保留剩余文字的逐字时间。
- 检查器里的每个词可点击跳到该处播放，并可清除这一行的逐字时间。

所有改动都是可撤销的编辑，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/1668401f-lyric-forge-ktv`，基于 main `7fc43e6a223d36659d34f5f348e7db6fad4896c6`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域服务**：`lyrics/domain/services/lyric_word_tap_session.dart`（新）——逐字打轴的状态：按键、松开、撤回、后退、重打本行，以及把整行按完的结果写回文档（逐字时间、行时间、手动打轴来源）。`lyric_asr_loop_detector.dart` 新增 `LyricAsrLoopPlan.keptWords`，`applyTo` 删减时保留剩余逐字时间。
- **转写**：`transcription/data/services/whisper_json_transcript_parser.dart` 新增 `segmentWords`。
- **界面（`lib/features/lyrics/presentation/`）**
  - `widgets/lyric_tap_controls.dart`（新）：`LyricTapClock`、`LyricTapPad`，行级打轴和逐字打轴共用。
  - `widgets/lyric_word_tap_dialog.dart`（新）：逐字打轴对话框。
  - `widgets/lyric_tap_sync_dialog.dart` 改用共用的时钟和按钮。
  - `lyric_batch_text_edit.dart`（`wordTap`）、`controllers/lyric_batch_text_tools_coordinator.dart`、`lyric_proofread_menu_button.dart`、`lyric_editor_toolbar.dart`、`lyric_editor_content.dart`。
  - `lyric_inspector_pane.dart`、`lyric_word_timing_strip.dart`：词可点击跳转，新增“清除”。
- **文档**：`decisions.md`（D-022）、本文件、工作日志条目 `2026-11-19-1200`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。

- `dart format`：改动文件已格式化。
- `flutter analyze`：没有 error 或 warning，186 条 info，与 main 相同。
- 目标测试 8 个文件，70 个测试全部通过（第一次运行发现 `[_TT_150]` 这类时间戳 token 没有被跳过，已修复）。
- `flutter test` 全量：2574 通过，2 跳过，0 失败（main 为 2555 通过）。
- `dart tool/work_log.dart write` 和 `check`：通过（warning 一条是旧条目，一条是本条目的提交标题要合并后才存在）。
- `lyric_editor_screen.dart`：仍为 1178 行。

## 下一步

- 用真实歌曲试逐字打轴的手感，按反馈调整默认反应补偿和行尾时长规则。
- 用 #413 的真实歌曲语料校准循环阈值，并对比 Whisper 逐词时间与 Qwen 对齐器的精度。
- 逐字打轴目前只能整行重打；可以考虑在检查器里拖动单个词的边界做微调。

## 已知风险

- 旧版本应用打开新工程会忽略 `words`，再保存时会丢掉逐字时间（行级时间不受影响）。
- 逐字时间按演唱字符数匹配；文字改动后字数不变但内容错位（例如调换顺序）时，逐字时间仍会被使用。
- 逐字打轴的精度取决于用户反应速度；反应补偿默认关闭。
- Whisper 的 token 分组规则是启发式的；分组后字数对不上就整段放弃，不会写入错误的逐字时间。

最后更新：2026-11-19 12:00（Asia/Taipei）
