# Handoff

## 目标

T0：完成 lyric proofreading v2 的只读契约核对，记录真实类名、源文件位置、Q1–Q8 现状与 T1–T9 拆分。当前 Draft PR 是文档审查阶段，不含 Dart 实现。

## Git 现场

- 仓库：`BrainEno/lyric-forge-ktv`。
- GitHub 已确认的基线：`main @ 165db5b5ee12ba6b238a24d6b859095525b562b1`（PR #129 已合并）。
- 工作分支：`docs/lyric-proofreading-v2-contracts-20261022`。
- 本执行环境没有本地 checkout；`git status --short`、`git diff --stat`、`git log --oneline -5` 无法从本地运行。尝试 `git ls-remote` 时 shell 无法解析 github.com，因此以当前 GitHub API 返回的 main/head 信息为远程快照，不伪造本地命令输出。

## 已改文件

- `docs/lyric_proofreading_v2_plan.md`：新增 T0 审计报告。
- `docs/work_log_index.md`：把已合并 PR #129 的过时 Draft 状态改为已合并，并标记 v2 为当前方向。
- `docs/handoff.md`：本交接记录。

未改 Dart 源码、测试、CI 或生成式 `docs/work_log.md`。没有新增 immutable work-log entry：项目要求先完成可验证的交付再记录，本环境不能运行 work-log 生成/检查工具。

## 检查结果

- 已核对：AGENTS.md、work_log_index、handoff、lyric_review_alignment_plan，以及 3 条与行标识/手动保护/时间来源直接相关的 log entries。
- 已核对源代码中的类名与关键调用点，并在 T0 文档中附路径与行号。
- 未运行：`dart format`、`flutter analyze --no-pub`、Flutter tests、`dart tool/work_log.dart write/check`。环境没有 Dart/Flutter 可执行文件和本地 checkout；shell 到 GitHub 的 DNS 访问失败。
- 最近一次仓库记录是歌词测试 215/215、全量测试 549/549 通过；这不是本次执行结果，细节见计划文档 Q8。

## 下一步（唯一）

开始 T1：先新增并运行任务要求的 tokenizer / sanitizer 测试，再实现三个纯 Dart 文件；不要在 T1 中顺手实现整条 proofread pipeline。

## 已知风险

- 当前 Qwen HTTP caller 没有传待对齐 transcript 字段；任意参考文本强制对齐能力尚未由当前调用路径证明。
- 当前 Whisper adapter 没有显式禁用上文条件；目标机器上的 whisper.cpp `--help` 尚未核实。
- 仓库文档称本地 vocal/instrumental separation backend 尚未完成；无 vocal stem 时使用 normalizedPath，再退回 originalPath。
- work-log 生成/检查仍待在有 Dart SDK 的本地 checkout 执行后再把 PR 标记为 ready。
