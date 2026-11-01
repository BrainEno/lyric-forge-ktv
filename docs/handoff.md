# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R8 逐项修复。Phase 0、Phase 1 的前五项、以及 R8（置信度语义）已完成；剩 1.6 Whisper 参数需真实语料验收，Phase 2 首启动需要真机。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/2417fd8c-lyric-forge-ktv`，基于 `main@037a431`。
- 该分支包含 R8（未评分不再当低置信度）；工作区在提交后应为 clean。
- 已合并：`fb99f4f`（Phase 0 工具，PR #274）、`f54f292`（R2 融合重复行，PR #275）、`f2d2f63`（上传用例 flake，PR #276）、`bade954`（整首一次识别 + 分片 metadata + 检查点指纹，PR #277）、`037a431`（Phase 1.5 降级，PR #278）。

## 已改文件

- `lib/features/project/domain/models/lyric_document.dart` — 新增 `LyricConfidenceSource`（`model`/`heuristic`/`unscored`）、`hasConfidenceScore`、`isLowConfidence(threshold)`、共享占位常量；JSON 往返保留来源，旧数据默认 `model`。
- `lib/features/transcription/domain/models/asr_confidence.dart` — 新增：两个引擎的纯评分函数（`scoreAsrLine` / `scoreWhisperSegment`）+ 可疑重复判定。
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`、`whisper_cpp_transcription_service.dart` — 无分数时标 `unscored`，规则调整过标 `heuristic`；不再伪造 50。
- `lib/features/transcription/data/services/high_quality_transcription_service.dart` — 融合决策产生的分数标 `heuristic`；副引擎独有行的截断值同样标 `heuristic`。
- `lib/features/lyrics/domain/proofreading/asr_consensus_analyzer.dart`、`asr_repetition_analyzer.dart`、`asr_first_pipeline.dart`、`asr_hallucination_filter.dart`、`lib/features/lyrics/domain/services/lyric_review_priority_service.dart` — 阈值一律走 `isLowConfidence(...)`；副引擎无分数时 `secondaryConfidence` 记 `null`。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart` — 行徽标显示「未评分」；复核计数/筛选按新语义；导入的第二份转写稿标 `unscored`。
- 测试：新增 `test/features/transcription/asr_confidence_test.dart`；改 `asr_first_pipeline_test.dart`、`asr_consensus_analyzer_test.dart`、`lyric_review_priority_service_test.dart`。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — R8 标注已修复（含刻意不改的两处）。
- `docs/log/entries/2026-11-01-2111-unscored-confidence.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.11.4）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - `dart format`（本次改动的 Dart 文件）=> 由 CI 自动应用并回推。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0。
  - 11 个受影响测试文件 => 全通过；`bash scripts/quality_gate.sh --skip-pub-get`（全量）=> 通过。
- `asr_confidence_test.dart` 直接锁评分契约：无分数 => `unscored` + 占位值；分数未被规则改动 => `model`；被规则下调 => `heuristic`；Whisper 段无 token 概率 => `unscored`；`[_BEG_]` 之类的非语音 token 不计入；JSON 保留来源；旧数据解析为 `model`。
- 消费侧测试锁语义而不是管道：两个未评分引擎的一致行现在 `green` 且无理由、`secondaryConfidence == null`；真有 40 分的行仍然产生 `lowConfidence` + `amber`；未评分行不出现在复核排序里，而同样数值 50 但有分数的行仍然出现。
- 占位值仍是 50，所以任何漏改的阈值都会立刻让测试失败，而不是悄悄回归。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：生成文件一致 + lint 0 error。
- PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 置信度（R8）的取舍：`LyricLine.confidence` 仍是非空 `int`（117 处读取），用「占位值 + 来源标记」表达「没分数」，而不是改成可空。刻意没改的两处写在审查文档 R8 小节：可疑幻觉清单仍把「无分数 + 无二次证据」列为候选；融合里 `qwenConfidence >= 55` 的采纳门槛保持不变。
- 已知噪声残留：`secondary == null`（只跑单引擎）时 ASR-first 管线仍把每一行标 `amber`，这是既有且有测试的依据的策略，属于 Phase 3.3 的后续项，不要误以为是 R8 没修干净。
- 触摸 `project_detail_screen.dart` 会顺带格式化该文件里约 195 行历史格式债（仓库门禁只格式化「本次改动的文件」）。这是格式化器的输出，不是重写；下一个改这个文件的人不会再付一次成本。
- 权威引擎仍决定全局断句：`qwenPrimary` 时输出就是 Qwen 的细分结果，属 R7 范围（Whisper 参数与 `--prompt` 尚未优化）。
- 20 分钟阈值是**策略选择而非实测结论**：没有真实语料证明 20 分钟比 3 分钟在长音频上更好，只是对歌曲而言两者等价于「整首一次」。若将来出现超长现场录音的质量投诉，先看接缝，而不是直接把阈值调回去。
- 检查点版本升到 2 会让所有旧检查点失效一次（有意的：旧检查点没有配置指纹）。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。
- **还有 1 个未定位的偶发失败**：14 次完整门禁里有 1 次（run 41295405781）在 `test/tool/forced_alignment_eval_test.dart` 的 provenance 输出附近失败；该文件单独跑 25 次不复现，之后的门禁也全绿，抓到的日志尾部不含失败用例自己的错误行，是**未知原因而非已修复**。若再次出现，先用临时工作流把 `[E]` 行转成 annotation 再抓（本环境无法下载 Actions 日志）。
- 历史遗留：PR #271 曾让 `main` 门禁变红（格式 + 死代码），已修复；现基线为绿。

## 下一步

1. Phase 1.6：Whisper 解码参数与 `--prompt`（R7），需要用 `--baseline --fail-on-regression` 验收（需要真实语料）。
2. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
3. Phase 2.1 首启动可安装性（R5）：只能在真机验收，需用户配合。
4. 偶发失败：已确认是 `test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving`（`SecureSocket.connect` 阶段 `Broken pipe`，该用例把 `totalTimeout` 设为 250ms）；PR #278 期间 4 次门禁出现 2 次，重跑即绿。此前记录的 `forced_alignment_eval_test.dart` 位置有误。

最后更新：2026-11-01 21:11（Asia/Taipei）
