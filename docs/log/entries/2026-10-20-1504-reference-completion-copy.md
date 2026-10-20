# [2026-10-20 15:04] 同步参考歌词补全文案

- Scope: C4 让纯文本参考也能补全漏行并推断时间，但输入对话框仍写着“纯文本只纠正文字”，时间轴不可用提示也写成“只纠正文字”。本次只同步用户可见文案，避免用户误以为纯文本不会补行；不改变任何行为。
- Files: `lib/features/lyrics/presentation/widgets/reference_alignment_dialog.dart`（标题说明改为“纠正并补全漏行、推断时间”；纯文本提示改为“纠正文字并补全漏行”）、`lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`（部分带时间戳/非一一对应时提示“只纠正文字并补全漏行”）、`docs/log/entries/2026-10-20-1504-reference-completion-copy.md`、`docs/work_log.md`、`docs/work_log_archive.md`。
- Validation: `flutter analyze --no-pub` → No issues found；`flutter test --no-pub test/features/lyrics/` → 95/95 通过。仅文案修改，未新增测试。
- Notes: 未运行全量测试套件，未做人工视口复核；`reference_alignment_dialog.dart` 未整体格式化，避免在既有大文件上产生无关 diff。
- Commit: `Clarify reference lyric completion copy`
