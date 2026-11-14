# Handoff

## 目标

继续推进 #319（不转向 #323）：安全地在智能校对 V2 复用已验证的独立第二引擎证据，并让参考歌词可与 ForcedAligner 组合生成独立、逐行可复核的时间证据。Whisper 原始 JSON 必须有界读取，且只有逐项匹配已通过音频校验的内嵌第二稿时才采用；否则回退快照。metadata-only 预览不授权比较，确认后仍检查工程 revision、当前音频和草稿。不要在最终质量门通过、验收证据审完之前关闭 #319 或宣称整项完成。

## Git 现场

当前分支 `arena/6929f1a1-lyric-forge-ktv`，基于 `48f5a75e19bdb8311f0ec7e52ceea9cc581b7985`。PR #437 仍 OPEN：https://github.com/BrainEno/lyric-forge-ktv/pull/437；GitHub API 显示 #319 是 OPEN issue（不是 PR），按要求保持 OPEN。最近一次完整 Flutter Quality Gate `43567672221` 在清理 head `14c7e840f25faf325455ba327569ac707b69de2f` 通过；对任何后续提交都应以 PR 当前 head 的 check rollup 为准。主要实现提交为 `b92967d Add verified project evidence preselection`，之后有格式、测试和验收证据跟进。

本轮临时加入的 `.github/workflows/followup-validation.yml` 与所有临时 PR 评论均已删除；不要将诊断 workflow 恢复到最终分支。

## 已改文件与验收核对

- `lib/features/transcription/data/services/whisper_json_transcript_parser.dart` 与 `whisper_json_artifact_reader.dart`：正式 Whisper 转写和 artifact 共用有界 parser；artifact 读取限制字节/路径、拒绝符号链接条目并严格解码。
- `lib/features/transcription/data/services/project_proofread_evidence_loader.dart`、`whisper_cpp_transcription_service.dart`、`project_proofread_evidence.dart`：preview 只返回 metadata hint；完整 load 重验 revision、当前音频、offset、engine、草稿及原始 JSON 与音频校验后内嵌快照的逐字段一致性；读取异常/缺失/不匹配回退到快照。
- `lib/features/lyrics/presentation/controllers/lyric_editor_proofreading_coordinator.dart`、V2 options/dialog、assembly/dependencies：匹配草稿的单次候选可默认选择，用户确认后加载；原始双引擎或分片候选保持只读/不参与不匹配草稿共识，并对不可用或被策略忽略的证据给出说明。
- 新增/扩展 parser、bounded artifact reader、loader、V2 widget、editor、assembly 和 `RunProofreadV2UseCase` 测试；本 follow-up 另加强 secondary 共识及无 `secondaryAsrUnavailable` 断言，并修正离屏 checkbox 测试的 `ensureVisible`。
- **#319 验收 1（代码/测试层面）：** coordinator 在确认后把已验证 `secondary` 传给独立 V2 use case；ASR-first pipeline 用它构建 consensus，secondary 存在时不生成 `secondaryAsrUnavailable`；loader/editor 集成与新增 use-case/pipeline 断言覆盖这条路径。尚未用真实 Highest Quality 歌曲工程做端到端准确率评测。
- **验收 2：** reference-first use case 把清洗后的参考文本交给 ForcedAligner；planner 将 token spans 合并为逐参考行提案并标记 `forcedAlignment(reference)`；domain 与 editor/review 测试覆盖来源及展示。
- **验收 3：** assembler 输出明确 explanation code，`LyricReviewStrings` 将被忽略的参考、第二稿或 ForcedAligner 选项映射为用户文案，相关单测覆盖。
- **验收 4：** `test/features/lyrics/domain/proofreading/run_proofread_v2_use_case_test.dart` 是无 Widget 的独立编排测试，覆盖策略、次稿路由、ForcedAligner 边界、保护行和异步行为。

以上是代码与自动化覆盖核对，不等同于完成 #319 的全部产品/真实音频验证。

## 检查结果

- `git diff --check`、`bash scripts/check_app_identifiers.sh`：通过。
- Pinned Flutter Quality Gate `43567672221`（head `14c7e840f25faf325455ba327569ac707b69de2f`）：所有步骤通过，包括 work-log preflight、changed-Dart format、vendored audio backend 和完整 repository quality gate；此为移除临时诊断 workflow 后的清理 head。
- Pinned follow-up run `43567279129`（head `6d3a8dc54aabb32fd8e2308ed4e885dbed359c06`）通过：`dart tool/work_log.dart write` 与 `check` 均 exit 0；lint 0 errors、1 个既有 commit-subject warning。`asr_first_pipeline_test.dart` 的 23 项、`run_proofread_v2_use_case_test.dart` 的 22 项，以及完整 `http_media_hub_upload_test.dart` 的 15 项均通过。
- 较早诊断 run `43566633532` 的单独 `--plain-name` deadline test 在 `SecureSocket.connect` 收到 `Connection reset by peer`，发生在发送 HTTP 请求之前；相同用例在整份上传测试文件与完整 repository quality gate 中通过。测试 helper 改为连接 `session.host` 广告端点，不再假设可选 loopback listener 一定可用。单独筛选时的 TLS reset 原因尚未确认，不称为 flaky，也不宣称其根因已修复。
- 完整质量门中新增的 V2 编排与 pipeline 覆盖通过；修复过的离屏 checkbox 测试没有再报错。work-log writer/check 在 pinned SDK 上实际运行。
- 本地没有 Dart/Flutter/FVM。没有真实歌曲音频评测；不宣称真实 Highest Quality 工程端到端行为或识别准确率提升。

## 下一步

1. 合并前始终核对 PR #437 当前 head 的完整 Flutter Quality Gate 为绿；本次没有执行合并。若 deadline 用例再次失败，区分 TLS 握手 reset 与 HTTP upload timeout，不未经新证据认定为 flaky。
2. #319 的四项验收已有代码/fixture/自动化覆盖，但 Highest Quality 真实工程端到端行为与真实歌曲识别效果仍待产品级验证；完成这些验证前保持 #319 OPEN。

## 已知风险

音频摘要和工程 revision 都是点时检查，不构成文件锁或模型内容认证。Whisper JSON 只在逐项匹配已校验快照后使用；分片快照不进入当前草稿共识。#319 仍缺真实歌曲和用户流程验证，因此不能宣称全 issue 完成、关闭 issue 或提升识别准确率。

最后更新：2026-11-07（UTC）
