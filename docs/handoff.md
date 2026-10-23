# Handoff

## 目标
推进歌词智能校对 V2 的 T7：让 reference-first 与 ASR-first 两条流水线共用同一套不变量断言，并用真实 pipeline 输出验证安全合同。

## Git 现场
- 基础分支：`main`，起点 `64fdb746780edee98f7df1195a839d30aa4981f5`（PR #163 已合并）。
- 当前分支：`test/proofread-pipeline-shared-invariants-20261024`；本任务 PR 尚待创建。
- 当前执行环境仅提供 GitHub API；没有本地 checkout，也无法直接运行 `dart` 或 `flutter` 命令。

## 已改文件
- `test/features/lyrics/domain/proofreading/helpers/proofread_pipeline_invariants.dart`：新增共享断言，覆盖输出与 verdict 一一对应、时间顺序/不重叠、300ms 最短时长、受保护行原样保留、深层输入不可变、稳定 ID、参考行索引唯一、重复文本重叠与音频边界。
- `test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart`：新增重复副歌与受保护行的共享不变量测试。
- `test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart`：将共有不变量应用到现有案例，并补齐缺少音频时长与越界时间的显式复核行为测试。
- `docs/lyric_proofreading_v2_plan.md`：完成 T7，并明确 ASR-first 不静默改写越界时间；越界行必须 `timingConflict` + amber。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`、本文件及对应 entry：记录当前结果与下一阶段。

## 检查结果
- 本次改动已写入新分支；GitHub Actions 尚未运行，因此不能宣称新增测试通过。
- PR #163 的上一任务已合并至 `main`，其最终质量门禁通过：645 项测试全部通过，work-log lint 为 0 错误、0 警告。
- 需由本 PR CI 验证新增 helper 与两个流水线测试的 analyzer、定向/全量测试和 work-log lint。

## 下一步
1. 检查并修复本 PR 的 CI 反馈，直到全量质量门禁通过。
2. 由用户审阅并合并后，推进 T8：在既有复核与撤销流程中接入策略选择和 verdict 分组，不新增旁路持久化写入。

## 已知风险
- 为了不静默重写 ASR 时间，越界区间可以在 proposal 中保留为源证据，但必须标记 `timingConflict` 并显示为 amber；helper 将该情形视为显式复核例外，而非安全结果。
- 新增共享 helper 尚未执行 Dart formatter/analyzer；格式和类型错误以 CI 结果为准。

最后更新：2026-10-24 03:06（Asia/Taipei）
