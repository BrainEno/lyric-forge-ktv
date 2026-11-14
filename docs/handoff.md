# Handoff

## 目标

继续推进 #319（不转向 #323）：共享 Whisper JSON 解析器；有界读取 `whisperRawJsonPath`，且只在结果逐项匹配已通过音频校验的内嵌第二稿时采用，否则回退快照。V2 用 metadata-only 预览提示候选，revision、所选音频和草稿核验留到确认后加载执行。未逐项核对完整验收并通过质量门前，不宣称 #319 完成或关闭。

## Git 现场

分支 `arena/6929f1a1-lyric-forge-ktv`（active），基于 `48f5a75e19bdb8311f0ec7e52ceea9cc581b7985`。实现已提交：`b92967d Add verified project evidence preselection`；PR 尚未创建。Issue #319 最新查询为 OPEN，验收标准来自 `gh issue view 319 --repo BrainEno/lyric-forge-ktv`。

`git status --short`（提交本 handoff 更新前）：

```text
 M docs/handoff.md
```

`git diff --stat`（提交本 handoff 更新前）：

```text
 docs/handoff.md | 65 +++++++++++++++++++++------------------------------------
 1 file changed, 24 insertions(+), 41 deletions(-)
```

`git log --oneline -5`（提交本 handoff 更新前）：

```text
b92967d Add verified project evidence preselection
48f5a75 Merge pull request #436 from BrainEno/arena/687794f2-lyric-forge-ktv
```

本轮 Dart 源码/测试增加 1,429 行、删除 108 行，超过每轮至少 800 行的要求。实现 commit 共 22 files changed, 1500 insertions(+), 130 deletions(-)；不含之后的 handoff-only 更新。

## 已改文件

- `lib/features/transcription/data/services/whisper_json_transcript_parser.dart` 与 `whisper_json_artifact_reader.dart`：正式 Whisper 转写和 artifact 共用 bounded parser；artifact 读取限制字节/路径、拒绝符号链接条目、检查变化并严格解码。
- `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`：切换到共享 parser。
- `lib/features/transcription/data/services/project_proofread_evidence_loader.dart`：新增只返回提示 metadata 的 `preview()`；完整 load 重新核对 revision、当前音频哈希与草稿，再逐字段比对 raw JSON 和已验证内嵌快照；读取失败、不匹配时回退快照。
- Evidence hint、editor dependency assembly/coordinator 与 V2 dialog：仅草稿匹配的单次候选默认选择；原始双引擎/分片只读，不可信状态显示提示。
- 新增 parser/artifact reader tests；扩展 loader、V2 widget/editor integration、assembly contract tests。
- `docs/lyric_proofreading_v2_plan.md`、ASR product follow-up、work-log entry/index/archive、handoff：记录当前边界与剩余验收。

## 检查结果

- `git diff --check`：通过（commit 前）。
- `bash scripts/check_app_identifiers.sh`：通过。
- 已尝试 `dart tool/work_log.dart write` 与 `check`，两者均因 `/bin/bash: dart: command not found` 退出 127。
- 无 Dart/Flutter/FVM；未运行 `dart format`、`flutter analyze`、新增及相关 Flutter tests。work-log 入口与导航已手动补齐，但 harness 尚未执行。当前 commit 无 PR/CI 结果，不能宣称这些检查通过。

## 下一步

提交本 handoff 更新后，只推送当前分支并创建 PR；使用 pinned Flutter Quality Gate 运行格式化、analyze、测试和 work-log check，修复失败。然后刷新 #319 并逐项核验四条验收标准，最终 head 全绿后再合并。

## 已知风险

#319 仍 OPEN，本轮仅完成工程证据预览/复用切片。完整验收仍须复核：Highest Quality 无粘贴时出现 consensus 且无 `secondaryAsrUnavailable`；参考歌词 + ForcedAligner 产生逐行 `forcedAlignment(reference)` 时间提案；被策略忽略的选项有明确文案；有独立编排单元测试。代码/已有测试可找到相关实现，但本轮未完整复验。哈希/revision 是点时校验而非文件锁或模型认证；没有真实歌曲音频评测，不宣称识别准确率提升。

最后更新：2026-11-07（UTC）
