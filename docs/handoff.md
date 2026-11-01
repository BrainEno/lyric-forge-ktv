# Handoff

## 目标
识别质量三步走：①`docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 记录根因与分阶段计划（已合并）；②把 PR #271 留下的红色门禁修绿（已合并）；③**Phase 0 质量基线工具**（本分支，`tool/asr_quality_report.dart`）。下一次会话应先拿到用户的人工校对语料、跑出真实基线，再动 Phase 1 的融合算法。

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/b3b7e45e-lyric-forge-ktv`，基于 `main@7e8c312`。
- 该分支包含 Phase 0 工具与文档；工作区在提交后应为 clean。

## 已改文件
- `tool/asr_quality_report.dart` — 新增行级质量报告工具（行召回 / 精确率 / CER / 重复行率 / 行数比 / 时间戳 MAE，含 `--baseline` 回归门禁）。
- `test/tool/asr_quality_report_test.dart` — 34 个测试（指标、重复判定、LRC/JSON/纯文本解析、语料聚合、基线对比、边界）。
- `docs/asr_quality_baseline.md` — 语料格式、指标口径、目标阈值、造语料建议。
- `.gitignore` — 忽略 `/corpus/`（真实歌曲与歌词不入库）。
- `docs/log/entries/2026-11-01-1354-line-quality-baseline-tool.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成/导航同步。
- `docs/handoff.md` — 本文件。

## 检查结果
- 本地无 Flutter/Dart SDK，本次同样用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.11.4）上验证，随后删除该 workflow 与报告文件：
  - `dart format`（两个新文件）=> 已格式化，无剩余差异。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => 新文件 0 处问题；仓库其余 40 条均为既有 info，exit 0。
  - `flutter test test/tool/asr_quality_report_test.dart` => `+34` 全通过。
  - `flutter test --no-pub`（全量）=> `+888 ~1` 全通过，exit 0。
  - CLI 冒烟：参考/输出对比 exit 0；语料模式写 JSON exit 0；与自身基线对比 exit 0；篡改基线使重复行率下降后 `--fail-on-regression` exit 1 并输出 `REGRESSION fused duplicateLineRate`；缺失语料与未知选项 exit 2。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：三个生成文件一致性 + lint 0 error。
- 相对链接存在性检查与 `git diff --check` 通过；PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险
- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）才能得出「重复行率到底是多少」。报告里预测的 >30% 仍是待验证的预测，不得当作结论引用。
- 报告中的量化重复行率来自对融合算法的 Python 复刻与合成语料，**不是**真实歌曲上的实测值。
- `test/high_quality_transcription_service_test.dart` 目前把「主行内部的一个词变成独立行」写成期望值，任何融合修复都会让该测试失败，必须同步改为新的契约。
- `docs/high_quality_asr.md`（整首一次送入）与 `docs/local_transcription.md`（3 分钟分片）互相矛盾，修复落地时需要一并订正。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。
- 历史遗留：PR #271 曾让 `main` 门禁变红（格式 + 死代码），已修复；现基线为绿。

## 下一步
1. 让用户跑出真实基线：准备 `corpus/corpus.json` + 每首歌的 `reference.lrc` / `whisper.lrc` / `fused.lrc`，执行 `dart run tool/asr_quality_report.dart --corpus corpus/corpus.json --output corpus/baseline.json`，把重复行率填进 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 Phase 0 验收行。
2. Phase 1 三项高收益修复（每项都用 `--baseline --fail-on-regression` 验收）：融合匹配重写（子串窗口相似度 + 被主行时间包住则不插入）、去掉全局 3 分钟分片、分片合并保留 metadata 且检查点指纹纳入配置。
3. Phase 1 其余项：Whisper 解码参数与 `--prompt`、最高质量模式自动降级；随后 Phase 2（Whisper 单模型全平台可安装）。

最后更新：2026-11-01 13:54（Asia/Taipei）
