# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R7 逐项修复。Phase 0（度量工具）与 Phase 1 的前四项已完成，下一步是 1.5/1.6。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/6d6b5c65-lyric-forge-ktv`，基于 `main@f2d2f63`。
- 该分支包含 Phase 1.1 / 1.3 / 1.4（整首一次识别、分片 metadata 重建、检查点指纹纳入配置）；工作区在提交后应为 clean。
- 已合并：`fb99f4f`（Phase 0 工具，PR #274）、`f54f292`（R2 融合重复行，PR #275）、`f2d2f63`（上传用例 flake，PR #276）。

## 已改文件

- `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart` — 默认分片阈值 3 分钟 → 20 分钟（`defaultChunkDuration`）；探测在创建会话目录之前；`_mergeDocuments` 产出索引映射，`_mergeMetadata` 重建 metadata；manifest 版本 2 + `configFingerprint`；`_shiftDocument` 平移候选时间；分片工作目录用后即删。
- `lib/core/services/service_locator.dart` — 装配处注明「整首一次」的原因。
- `test/resumable_chunked_transcription_service_test.dart` — 新增 3 个用例（整首一次 / 合并重映射 / 改配置使检查点失效）；原检查点用例显式指定 3 分钟分片。
- `docs/local_transcription.md` — 重写 Resumable 一节（20 分钟阈值、metadata 重建、检查点随配置失效）。
- `docs/high_quality_asr.md` — 补一句包装器阈值，消除与 `local_transcription.md` 的矛盾。
- `docs/asr_quality_baseline.md` — 两处「3 分钟接缝」表述更新。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — R1/R3/R4 标注已修复，并写明取舍与未处理项。
- `docs/log/entries/2026-11-01-2005-whole-song-recognition.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.11.4）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - `dart format`（两个改动文件）=> 0 changed。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0（本次引入的 1 条 `unused_element_parameter` 警告已删除，其余为既有 info）。
  - 受影响测试文件（`resumable_chunked` / `transcription_execution_failure_kind` / `high_quality_transcription_service`）=> 全通过。
  - `bash scripts/quality_gate.sh --skip-pub-get`（全量）=> 通过。
- 新增用例锁定三条契约：5 分钟的歌只调用一次 delegate 且不产生 `chunk_session`；两片合并后 `secondaryOnlyLineIndices` 重映射为 `[1, 2]`、`suspiciousLineIndexes` 为 `[0, 2]`、候选时间平移到歌曲时间；同配置复用检查点（delegate 不再调用）、换模型重跑两片。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：生成文件一致 + lint 0 error。
- 相对链接存在性检查与 `git diff --check` 通过；PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 权威引擎仍决定全局断句：`qwenPrimary` 时输出就是 Qwen 的细分结果，属 R7 范围（Whisper 参数与 `--prompt` 尚未优化）。
- 20 分钟阈值是**策略选择而非实测结论**：没有真实语料证明 20 分钟比 3 分钟在长音频上更好，只是对歌曲而言两者等价于「整首一次」。若将来出现超长现场录音的质量投诉，先看接缝，而不是直接把阈值调回去。
- 检查点版本升到 2 会让所有旧检查点失效一次（有意的：旧检查点没有配置指纹）。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。
- **还有 1 个未定位的偶发失败**：14 次完整门禁里有 1 次（run 41295405781）在 `test/tool/forced_alignment_eval_test.dart` 的 provenance 输出附近失败；该文件单独跑 25 次不复现，之后的门禁也全绿，抓到的日志尾部不含失败用例自己的错误行，是**未知原因而非已修复**。若再次出现，先用临时工作流把 `[E]` 行转成 annotation 再抓（本环境无法下载 Actions 日志）。
- 历史遗留：PR #271 曾让 `main` 门禁变红（格式 + 死代码），已修复；现基线为绿。

## 下一步

1. Phase 1.5：最高质量模式在 Qwen 不可用时自动降级到 Whisper（现在直接失败，R6）。
2. Phase 1.6：Whisper 解码参数与 `--prompt`（R7），需要用 `--baseline --fail-on-regression` 验收。
3. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
4. 复现并修掉剩下的那个偶发失败（`forced_alignment_eval_test.dart` 附近，14 次门禁出现 1 次）。

最后更新：2026-11-01 20:05（Asia/Taipei）
