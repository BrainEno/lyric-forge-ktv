# Handoff

## 目标
T5 phase 3：增加保守的疑似 ASR 幻觉候选过滤。只生成可人工复核的候选，不删除歌词、不改文本或时间轴。

## Git 快照
- PR #143：`feat/lyric-proofreading-t5-hallucination-20261022` → `main`，Draft；基线 main SHA `b736c61d1b714fda459d0370be915d082a6e1c17`。
- PR #143 测试先行提交：`b621dbddd4129d2b887973b02a4eed2de979e8e3`；初始实现提交：`178b604483660260bb4397cbf2af1648c8085a06`。
- PR #144：`fix/port-t5-repetition-to-main` → `main`，Draft。背景：PR #142 被合并进旧的 #141 功能分支，而不是最新 `main`，所以重复片段模块不在 `main`。
- 本环境只有 GitHub API，没有本地 checkout；无法获取 `git status --short`、`git diff --stat` 或 `git log --oneline -5` 的本地输出。

## 已改文件
- `lib/features/lyrics/domain/proofreading/asr_hallucination_filter.dart`：只标记低置信度、无第二引擎时间重叠且没有近邻次引擎独有行的候选。
- `test/features/lyrics/domain/proofreading/asr_hallucination_filter_test.dart`：覆盖候选、置信度阈值、重叠文本分歧、近邻时间抑制、远邻证据、空文本、不可变结果。
- `docs/lyric_proofreading_v2_plan.md`、`docs/work_log_index.md`、`docs/handoff.md`：记录 #142 未进入 main 的集成事实和 T5 当前阶段。

## 检查结果
- 静态检查：过滤器只消费共识结果；保留原始 LyricLine 与索引；候选带有低置信度和无次引擎重叠两条原因码；没有落盘、删行或改时间。
- 未运行 `dart format`、新测试、`flutter analyze --no-pub`、`flutter test test/features/lyrics` 或 `dart tool/work_log.dart check`；无对应 CI 结果。
- 未创建 immutable work-log entry，未手动编辑生成的 `docs/work_log.md`。

## 下一步（唯一）
先在本地检出最新 `main`，运行 PR #143 和 PR #144 描述中的格式化、定向测试、analyze、歌词回归测试和 work-log 检查；确认通过后，按依赖顺序合入 PR #144（重复片段模块移植）和 PR #143（幻觉候选过滤），并在合入后更新计划状态。

## 已知风险
无第二引擎匹配不是歌词幻觉的充分证据。因此只有低置信度且存在时间轴孤立证据时才列为疑似候选；近邻 secondary-only 行会抑制候选以避免把 ASR 分段/时间漂移误判为幻觉。候选暂未进入 UI 或真正的 dropped/恢复交互。
