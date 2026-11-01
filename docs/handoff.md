# Handoff

## 目标
本次只有文档产物：`docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 记录「识别结果比第一版更差」与「编辑器/导航过复杂」的源码级根因与分阶段计划。代码没有任何改动，下一次会话应从下面「下一步」的第 1 条开始执行修复。

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/db5dfc01-lyric-forge-ktv`，基于 `main@36104d3`（Merge PR #271）。
- 本分支只包含 1 个文档提交；工作区在提交后应为 clean。

## 已改文件
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — 新增审查报告（根因、证据索引、分阶段计划、低风险改动清单）。
- `docs/log/entries/2026-11-01-1156-recognition-quality-ux-review.md` — 本次任务的唯一工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成/导航同步（index 增加报告指针，并顺手订正已过期的 Media Hub #224 条目）。
- `docs/handoff.md` — 本文件。

## 检查结果
- 本地无 Flutter/Dart SDK，因此 `dart tool/work_log.dart check`、`flutter analyze`、`flutter test` 均未运行，也不声称通过。
- 使用逐行复刻 `tool/work_log.dart` 语义的本地脚本：先对**提交前**的仓库状态重建 `docs/work_log.md`、`docs/work_log_archive.md` 与 index 快照日期，三者与仓库中文件逐字节一致；再新增条目重算，lint 规则 0 error。
- 文档内相对链接存在性检查通过；`git diff --check` 通过。
- 本次没有改动任何 `.dart` 文件，Flutter Quality Gate 的结论与 `main@36104d3` 相同。

## 下一步
1. Phase 0：建立质量基线（人工校对 5–10 首歌 + `tool/asr_quality_report.dart`，输出行召回、CER、重复行率、时间戳边界误差）。
2. Phase 1 三项高收益修复：`high_quality_transcription_service.dart` 融合匹配（子串窗口相似度 + 被主行时间包住则不插入）、`service_locator.dart` 去掉全局 3 分钟分片、`resumable_chunked_transcription_service.dart` 合并时保留 metadata 且检查点指纹纳入配置。
3. Phase 1 其余项：Whisper 解码参数与 `--prompt`、最高质量模式自动降级；随后 Phase 2（Whisper 单模型全平台可安装）。

## 已知风险
- 报告中的量化重复行率来自对融合算法的 Python 复刻与合成语料，**不是**真实歌曲上的实测值；真实数字必须由 Phase 0 的语料给出。
- `test/high_quality_transcription_service_test.dart` 目前把「主行内部的一个词变成独立行」写成期望值，任何融合修复都会让该测试失败，必须同步改为新的契约。
- `docs/high_quality_asr.md`（整首一次送入）与 `docs/local_transcription.md`（3 分钟分片）互相矛盾，修复落地时需要一并订正。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。

最后更新：2026-11-01（Asia/Taipei）
