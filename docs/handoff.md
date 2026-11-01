# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R7 逐项修复。Phase 0 与 Phase 1 的前五项已完成（剩 1.6 Whisper 参数，需真实语料验收）。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/1680b6b3-lyric-forge-ktv`，基于 `main@bade954`。
- 该分支包含 Phase 1.5（最高质量模式在第二引擎不可用时降级为 Whisper）；工作区在提交后应为 clean。
- 已合并：`fb99f4f`（Phase 0 工具，PR #274）、`f54f292`（R2 融合重复行，PR #275）、`f2d2f63`（上传用例 flake，PR #276）、`bade954`（整首一次识别 + 分片 metadata + 检查点指纹，PR #277）。

## 已改文件

- `lib/features/transcription/domain/models/transcription_degradation.dart` — 新增：降级原因枚举 + metadata 读写助手（服务写入、UI 读取共用一套键名）。
- `lib/features/transcription/domain/models/transcription_models.dart` — `isConfigured` 改为「Whisper 基线可用」，新增 `runsDualEngine` / `willDegradeToWhisper`。
- `lib/features/transcription/domain/services/asr_runtime_manager.dart` — 新增 `isBaselineReady` / `missingBaselineComponents`。
- `lib/features/transcription/domain/services/transcription_environment_preflight.dart`、`transcription_queue_environment_recovery.dart` — 只按基线判定就绪。
- `lib/features/transcription/data/services/high_quality_transcription_service.dart` — 配置级与运行级降级，`_canDegradeToWhisper` 判定哪些错误不该降级。
- `lib/features/transcription/data/services/local_project_transcription_workflow.dart` — 门禁改用基线；工程 metadata 记录 `degraded` / `degradationReason`。
- `lib/features/project/presentation/screens/project_detail_screen.dart` — 「识别模式」标注「已降级为单引擎」+ 新增「识别降级」行；「开始识别」按钮只被基线缺失拦截。
- 测试：`transcription_config_test.dart`、`asr_runtime_status_test.dart`、`high_quality_transcription_service_test.dart`、`transcription_environment_preflight_test.dart`、`transcription_queue_environment_recovery_test.dart`、`transcription_queue_protective_pause_contract_test.dart`。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — R6 标注已修复（含决策表与「哪些错误不降级」的理由）。
- `docs/log/entries/2026-11-01-2039-degrade-when-second-engine-missing.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.11.4）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - `dart format`（本次改动的 14 个文件）=> 0 changed。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0。
  - 受影响测试文件 => 全通过；`bash scripts/quality_gate.sh --skip-pub-get`（全量）=> 通过。
- 新测试锁的是行为而非实现：只配 Whisper 的最高质量请求只调用 Whisper 一次、完全不碰 Qwen，并写入 `degraded` + `qwenNotConfigured`；Qwen 运行期失败会产出保留原始错误文本的 Whisper 草稿并复用已归一化音频；`input` 与 `cancelled` 不降级；两个引擎都坏时错误信息同时包含两个原因；Whisper 基线缺失是阻塞性环境错误。
- `AsrRuntimeStatus.isBaselineReady` 两个方向都有覆盖（缺第二引擎 = 基线就绪但未完全就绪；缺 Whisper 模型 = 阻塞并指名组件）。
- 预检与队列恢复各新增一例，证明「缺第二引擎仍可导入 / 仍会恢复队列，缺 Whisper 仍需要安装 / 仍保持暂停」。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：生成文件一致 + lint 0 error。
- 相对链接存在性检查与 `git diff --check` 通过；PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 触摸 `project_detail_screen.dart` 会顺带格式化该文件里约 195 行历史格式债（仓库门禁只格式化「本次改动的文件」）。这是格式化器的输出，不是重写；下一个改这个文件的人不会再付一次成本。
- 权威引擎仍决定全局断句：`qwenPrimary` 时输出就是 Qwen 的细分结果，属 R7 范围（Whisper 参数与 `--prompt` 尚未优化）。
- 20 分钟阈值是**策略选择而非实测结论**：没有真实语料证明 20 分钟比 3 分钟在长音频上更好，只是对歌曲而言两者等价于「整首一次」。若将来出现超长现场录音的质量投诉，先看接缝，而不是直接把阈值调回去。
- 检查点版本升到 2 会让所有旧检查点失效一次（有意的：旧检查点没有配置指纹）。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。
- **还有 1 个未定位的偶发失败**：14 次完整门禁里有 1 次（run 41295405781）在 `test/tool/forced_alignment_eval_test.dart` 的 provenance 输出附近失败；该文件单独跑 25 次不复现，之后的门禁也全绿，抓到的日志尾部不含失败用例自己的错误行，是**未知原因而非已修复**。若再次出现，先用临时工作流把 `[E]` 行转成 annotation 再抓（本环境无法下载 Actions 日志）。
- 历史遗留：PR #271 曾让 `main` 门禁变红（格式 + 死代码），已修复；现基线为绿。

## 下一步

1. Phase 1.6：Whisper 解码参数与 `--prompt`（R7），需要用 `--baseline --fail-on-regression` 验收。
2. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
3. 复现并修掉剩下的那个偶发失败（`forced_alignment_eval_test.dart` 附近，14 次门禁出现 1 次）。

最后更新：2026-11-01 20:39（Asia/Taipei）
