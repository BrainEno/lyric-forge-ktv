# Handoff

## 目标
识别质量三步走：①`docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 记录根因与分阶段计划（已合并）；②把 PR #271 留下的红色门禁修绿（已合并）；③**Phase 0 质量基线工具**（已合并）；④**Phase 1.2 融合重复行修复**（本分支）。下一步是 R1/R3/R4（去全局分片 + 保留 metadata + 检查点指纹）。

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/40c97524-lyric-forge-ktv`，基于 `main@fb99f4f`。
- 该分支包含 Phase 1.2 融合修复与质量工具的重复判定修正；工作区在提交后应为 clean。

## 已改文件
- `lib/features/transcription/data/services/high_quality_transcription_service.dart` — 碎片「文本+时间都被主行包含」时判为同一句，不再插入。
- `tool/asr_quality_report.dart` — 重复判定增加「时间区间嵌套」条件（原先只比起始时间，漏掉嵌套碎片）。
- `test/high_quality_transcription_service_test.dart` — 新增 2 组回归测试；原先断言缺陷行为的用例改为只保留真正新增的歌词行。
- `test/tool/asr_quality_report_test.dart` — 新增嵌套重复用例。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — R2 按实测重写（原稿的 48/48、72/72 与 >30% 被实测推翻）。
- `docs/asr_quality_baseline.md` — 重复判定规则更新。
- `docs/log/entries/2026-11-01-1700-fusion-duplicate-rows.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成/导航同步。
- `docs/handoff.md` — 本文件。

## 检查结果
- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.11.4）上验证，随后删除该 workflow 与报告文件：
  - `dart format`（全部改动文件）=> `Formatted 4 files (0 changed)`。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => 改动文件 0 处问题；其余 41 条为既有 info，exit 0。
  - `flutter test`（两个受影响测试文件）=> `+49` 全通过。
  - `flutter test --no-pub`（全量）=> `+892 ~1` 全通过，exit 0。
  - 实测 A/B（真实服务，6 组粒度）：Whisper 权威、12 秒整行 / 3 秒碎片 从 27 行（插入 15、精确率 44.4%）变为 12 行（插入 0、100%）。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：三个生成文件一致性 + lint 0 error。
- 相对链接存在性检查与 `git diff --check` 通过；PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险
- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）才能得出「重复行率到底是多少」。报告里预测的 >30% 仍是待验证的预测，不得当作结论引用。
- 融合修复的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 权威引擎仍决定全局断句：`qwenPrimary` 时输出就是 Qwen 的细分结果（实测 40 行），属 R1/R7 范围，本次未处理。
- `test/high_quality_transcription_service_test.dart` 目前把「主行内部的一个词变成独立行」写成期望值，任何融合修复都会让该测试失败，必须同步改为新的契约。
- `docs/high_quality_asr.md`（整首一次送入）与 `docs/local_transcription.md`（3 分钟分片）互相矛盾，修复落地时需要一并订正。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。
- 历史遗留：PR #271 曾让 `main` 门禁变红（格式 + 死代码），已修复；现基线为绿。

## 下一步
1. Phase 1.1 / 1.3 / 1.4（同一批动 `service_locator.dart` 与 `resumable_chunked_transcription_service.dart`）：去掉歌曲流程的全局 3 分钟分片、分片合并保留 metadata（含 `fallbackCandidates` 索引重映射）、检查点指纹纳入 ASR 配置。
2. Phase 1.5 / 1.6：最高质量模式在 Qwen 不可用时自动降级；Whisper 解码参数与 `--prompt`。
3. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。

最后更新：2026-11-01 13:54（Asia/Taipei）
