# [2026-10-19 23:52] 歌词编辑器接入进度条并支持暂停定点插入行

- Scope: 编辑器此前只有播放/暂停和绝对时间文本，无法拖到目标位置，新增行也只能追加到末尾。本轮让编辑器试听条可悬停/点击/拖动跳转（跳转前自动暂停），并新增"在播放位置插入"：暂停到遗漏歌词的时间点后一键插入，新行按开始时间落到正确索引，自动选中并聚焦输入框，保存后仍保持顺序。
- Files: `lib/features/lyrics/domain/services/lyric_timeline_insertion_service.dart`（新增纯规则：二分位置、下一行开始时间、+5s 兜底、10ms 最小区间）、`lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`（工具栏接入共享进度条，插入逻辑、紧凑布局底部栏按钮、列表聚焦请求、检查器 autoFocus）、`test/features/lyrics/domain/services/lyric_timeline_insertion_service_test.dart`（6 个规则测试）、`docs/lyric_review_alignment_plan.md`（阶段 B 标记完成）。
- Validation: `dart format`（新增 service 与测试）；`flutter analyze lib/features/lyrics/ lib/features/player/ test/features/lyrics/` 无 error/warning（42 条均为既有 info，本次未新增）；`flutter test test/features/lyrics/ test/features/player/` 95/95 通过；`dart tool/work_log.dart check` 通过（仅新提交未入库的预期 warning）。未启动真实桌面窗口，布局与聚焦手感需人工确认。
- Notes: 未做"裁剪上一行结束时间"——若在某一行区间内插入，新行会与该行末尾重叠；LRC 与播放器按 startTime 取当前行，暂不视为错误，后续若需要可在插入服务中加开关。紧凑布局插入后通过列表 `didUpdateWidget` 自动打开行检查器并聚焦；双栏用带 `focusRequestId` 的 key 强制重建检查器以触发 autoFocus。项目编辑器文件较大且仓库未统一新格式，仅对新增文件执行 `dart format`。
- Commit: `Add lyric editor progress bar and insert-at-playback`
