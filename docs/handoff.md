# Handoff

## 目标
继续歌词智能校对 V2 主线：让 ForcedAligner 的词级时间证据不仅可见，还能逐词试听，以便人工检查边界；仍不自动覆盖歌词行时间戳。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 最新 main 基线：PR #185 已合并，merge commit `82a90b28f958e6752738eae8ac335b1cbd4550ed`。
- 当前开发分支：`feat/forced-align-token-audition-20261026`。
- 本分支增加复核卡片的词级证据展开与逐词试听回调；已添加 widget regression test，等待最新 head 的远端 Flutter Quality Gate。
- 当前执行环境没有本地 Dart/Flutter SDK，不能声称本地格式化、分析或测试通过。

## 已改文件
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`
- `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`
- `docs/work_log_index.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/handoff.md`
- `docs/log/entries/2026-10-26-1505-audition-forced-align-tokens.md`

## 本轮实现
- `LyricProofreadV2ReviewItem` 现在可以携带逐词 `TimedLyricToken` 证据。
- 复核卡片新增可折叠的词级证据区域，显示词语、起止时间和证据置信参考。
- 每个词有独立试听按钮，使用现有 `LyricAuditionWindowService`，提供 250 ms 预滚并尊重全局 offset、音频时长和行级 bounded audition 生命周期。
- 普通逐行试听抽取为共同的 bounded-window 播放入口，词级试听与原行试听共用切换项目、seek、暂停边界逻辑。
- 点击词语试听只改变播放器状态和当前选中行；不会改写任何歌词内容、时间戳、置信度或保存工程。
- 新增 widget 测试验证证据展开、时间显示、点击回调的行索引及 token 对象。

## 检查结果
- 已通过 GitHub 文件 API 核实修改内容与测试存在。
- 未在本执行环境运行本地 Dart/Flutter 命令；当前 PR 的最新 head 远端 CI 是最终验证依据。

## 下一步
- 等待最新 Flutter Quality Gate 和相关 ASR 契约检查；失败时按实际日志修复。
- 验证中、英、日真实音频的 token 匹配准确率、可试听边界及多行覆盖情况。
- 在真实样本达到验收门槛后，再单独设计显式确认的歌词时间修复动作；在此之前，token 时间只用于人工复核。

## 已知风险
- ForcedAligner 的契约/界面测试不证明真实歌曲的 token 时间准确度。
- 已安装 runtime bundle 需要包含原生 `POST /v1/align` endpoint，旧 bundle 必须重建后才可使用。
- 用户手动确认和保存仍沿用现有歌词校对安全流程；本轮不引入新的行时间自动应用机制。

最后更新：2026-10-26 15:05（Asia/Taipei）
