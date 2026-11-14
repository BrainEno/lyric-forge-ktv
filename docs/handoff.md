# Handoff

## 目标

继续推进 #319（不转向 #323）：安全地在智能校对 V2 复用已验证的独立第二引擎证据，并让参考歌词可与 ForcedAligner 组合生成独立、逐行可复核的时间证据。Whisper 原始 JSON 必须有界读取，且只有逐项匹配已通过音频校验的内嵌第二稿时才采用；否则回退快照。metadata-only 预览不授权比较，确认后仍检查工程 revision、当前音频和草稿。不要在最终质量门通过、验收证据审完之前关闭 #319 或宣称整项完成。

## Git 现场

当前分支 `arena/6929f1a1-lyric-forge-ktv`（PR 已打开），基于 `48f5a75e19bdb8311f0ec7e52ceea9cc581b7985`。PR #437 仍 OPEN：https://github.com/BrainEno/lyric-forge-ktv/pull/437；#319 最近刷新仍 OPEN。主要实现提交为 `b92967d Add verified project evidence preselection`，其后有格式修复、测试修复和 handoff/work-log 跟进。当前 follow-up 包含 formatter CI 精确输出、V2 证据选项滚动测试修正，以及 consensus/no-missing-secondary 断言；以远端 PR head 与 `git status -sb` 为准。

曾为定位 formatter 和测试问题临时加过 GitHub Actions 诊断工作流；这些文件已从分支树移除，诊断 PR 评论也已删除。不要恢复它们。

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
- 最新已完成 Flutter Quality Gate `43564036045`（head `454e97d`）：SDK setup、work-log contract preflight、依赖解析、changed-Dart format check、vendored audio backend tests 均通过；repository quality gate 跑到全量测试阶段。测试摘要 `+1972 ~1 -1`，唯一明确失败项为无关的 `test/features/transfer/http_media_hub_upload_test.dart: total upload deadline applies while chunks continue arriving`。因此这个 run **不是绿灯**，需要在 follow-up head 重跑。
- 同次 run 中，本次修复过的离屏 checkbox 测试没有再报错。`test/architecture_layer_imports_contract_test.dart` 在诊断 run `43563940450` 的定向测试中通过；完整套件的失败摘要仍带有该组 `tearDownAll` 行，需以最终完整质量门结果为准。
- 分析器在 gate 中先于测试运行；工作日志 preflight、格式检查和 vendored backend 均已通过。完整质量门尚未通过。
- 本地没有 Dart/Flutter/FVM；尚未在本机运行新加的 follow-up 断言。官方 `dart tool/work_log.dart write/check` 需要通过 pinned Flutter CI 补跑，不能据手工编辑宣称已运行。
- 没有真实歌曲音频评测；不宣称识别准确率提升。

## 下一步

1. 用 pinned Flutter SDK 跑本 follow-up 的新 consensus/pipeline 测试及 Media Hub deadline 用例，执行 `dart tool/work_log.dart write` 与 `dart tool/work_log.dart check`；检查并应用 harness 生成的 `work_log.md` / archive / index 差异，移除诊断工作流和临时评论。
2. 推送更新后等待最终 head 的完整 Flutter Quality Gate；如 HTTP deadline 用例再次失败，先根据定向重跑确认是否为既有时序脆弱测试，再决定是否需要小范围修复，避免将无关实现变更混入本切片。
3. 最终刷新 PR #437 和 Issue #319 状态，逐条确认四项验收；当前 #319 保持 OPEN。本任务未得到明确要求前不合并 PR。

## 已知风险

音频摘要和工程 revision 都是点时检查，不构成文件锁或模型内容认证。Whisper JSON 只在逐项匹配已校验快照后使用；分片快照不进入当前草稿共识。#319 仍缺真实歌曲和用户流程验证，因此不能宣称全 issue 完成、关闭 issue 或提升识别准确率。

最后更新：2026-11-07（UTC）
