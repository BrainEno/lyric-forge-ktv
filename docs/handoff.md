# Handoff

## 目标
推进歌词智能校对 V2 的 ASR-first 双转写证据输入；在不自动改写歌词的前提下，让第二份带时间戳的转写稿参与现有共识分析。

## Git 现场
- 基线：`main` 已合并 PR #178（ASR 安装失败进度与诊断复制修复）。
- 工作分支：`feat/asr-first-secondary-transcript-input-20261025`。
- 本次改动通过独立 PR 提交；main 不直接写入功能变更。
- 当前执行环境没有本地 repository checkout，也没有 Dart/Flutter 执行文件；远端 GitHub Actions 用作代码质量门禁。

## 已改文件
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`：ASR 优先策略新增可选的第二份带时间戳转写稿输入。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`：解析 LRC/SRT/WebVTT，仅在每行都有时间戳时传入现有 ASR 共识分析；无置信度元数据时保守设为 60。
- `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`：覆盖第二份转写稿输入值回传。
- `docs/log/entries/2026-10-25-1530-add-secondary-asr-transcript-input.md` 与工作日志导航：记录功能边界和验证限制。

## 检查结果
- 已检查现有 dialog 契约：取消通过 Navigator 返回 null；绿色专用操作只包含 locked 与 green 提案，不包含 amber 或灰色恢复项。
- 本环境未运行 `dart format`、`flutter analyze`、定向 Flutter tests 或 `dart run tool/work_log.dart check`，原因是没有本地 checkout 与 SDK。
- 新增 widget 回归测试；GitHub Actions Flutter Quality Gate 必须通过后才允许合并。

## 下一步
- 观察本 PR 的 GitHub Actions；若失败，修复后在同一分支重跑。
- 验证本 PR 的格式、分析、全量 Flutter 测试与 work-log lint。
- 后续继续研究 ForcedAligner 是否有已验证的任意文本对齐端点；在接口和时间边界未证实前，不得将 context 提示冒充强制对齐。

## 已知风险
- 测试环境不能替代 Windows + RTX 5080 上的真实歌曲自检；合并的运行时修复仍需在新 runtime v2 发布后验证。
- 第二份转写输入目前仅接受全行带时间戳的 LRC/SRT/WebVTT；纯文本第二转写需先有可靠的时间证据策略。
- 任意参考文本 ForcedAligner 适配尚未完成。
- 真实行试听、窗口尺寸矩阵以及应用后撤销仍需手动验收。

最后更新：2026-10-25 15:30（Asia/Taipei）
