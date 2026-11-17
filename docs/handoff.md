# Handoff

## 目标

让逐字时间（`LyricLine.words`）可以从已有的卡拉 OK 文件导入，能在全曲范围检查，并能逐个字微调：

- 导入逐字 LRC（`<mm:ss.xx>` 或行内 `[mm:ss.xx]`）、ASS（`\k` / `\kf` / `\K` / `\ko`）和带行内时间戳的 WebVTT 时保留逐字时间；本应用导出的逐字 LRC 和 ASS 可以原样导回。
- 「校对」菜单新增“逐字时间检查”：清除失效的逐字时间、保存已映射的结果，并列出拖长、过短和行内长停顿的字。识别摘要卡新增“逐字时间失效 N 行”提示。
- 检查器的逐字时间新增“微调”：选中一个字调整开始、结束，试听，设为播放位置，合并或拆开。没有逐字时间的行可以从按字数估算开始微调。

所有改动都是可撤销的编辑，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/05465f08-lyric-forge-ktv`，基于 main `5ab58aab18c19843a36ab175ae5e1284f9677d58`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域服务（`lib/features/lyrics/domain/services/`）**
  - `lyric_karaoke_tag_parser.dart`（新）：解析 LRC、ASS、WebVTT 行内的逐字标签，生成去掉标签的文字和逐字时间。
  - `lyric_word_timing_auditor.dart`（新）：逐字时间检查。
  - `lyric_word_timing_editor.dart`（新）：逐字微调的纯函数编辑（移动边界、平移、合并、拆分、写回行和时间来源）。
  - `lyric_file_import_service.dart`（`wordTimedRows`）、`lyric_draft_health_service.dart`（`staleWordRows`）。
- **导入**：`lyrics/data/services/local_lyric_file_import_service.dart` 调用解析器；`player/presentation/widgets/local_song_lyrics_import_action.dart` 的成功提示显示带逐字时间的行数。
- **界面（`lib/features/lyrics/presentation/`）**
  - `widgets/lyric_word_timing_check_dialog.dart`（新）、`widgets/lyric_word_timing_edit_dialog.dart`（新）。
  - `lyric_batch_text_edit.dart`（`wordTimingCheck`、`wordTimingEdit`）、`controllers/lyric_batch_text_tools_coordinator.dart`、`lyric_proofread_menu_button.dart`、`lyric_editor_toolbar.dart`、`lyric_editor_content.dart`、`lyric_recognition_summary_card.dart`。
  - `lyric_inspector_pane.dart`、`lyric_word_timing_strip.dart`：“微调”按钮，以及“逐字微调（从估算开始）”。
- **文档**：`decisions.md`（D-023）、本文件、工作日志条目 `2026-11-20-1200`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。

- `dart format`：最终代码无改动。
- `flutter analyze`：0 个 error/warning，186 个 info（与 main 相同，没有新增）。
- 目标测试 73 个通过；全量测试 2603 个通过、2 个跳过、0 个失败（main 为 2574 个）。
- 工作日志 `write` 和 `check` 通过。
- `lyric_editor_screen.dart` 保持 1178 行。

## 下一步

- 用真实的卡拉 OK 文件（网易云、QQ 音乐导出的逐字 LRC，Aegisub 做的 ASS）验证导入；QRC / YRC 这类专有格式目前不支持。
- 用真实歌曲校准逐字时间检查的阈值（拖长 2.5 秒、过短 40 毫秒、行内停顿 1.2 秒）。
- 行内长停顿可以直接提供“在此拆行”的修复，复用按逐字时间拆分。

## 已知风险

- 旧版本应用打开新工程会忽略 `words`，再保存时会丢掉逐字时间（行级时间不受影响）。
- 逐字时间按演唱字符数匹配；文字改动后字数不变但内容错位（例如调换顺序）时，逐字时间仍会被使用。
- LRC 文字里原本就有的方括号时间戳（不是逐字时间）现在会被当作逐字时间读入。

最后更新：2026-11-20 12:00（Asia/Taipei）
