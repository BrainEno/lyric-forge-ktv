# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R11 逐项修复。Phase 0、Phase 1 的前五项、R8（置信度语义）、R9（Qwen 解码预算）、Phase 3.1（校对入口合一）已完成；剩 1.6 的 Whisper 参数需真实语料验收，Phase 2 首启动需要真机。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/f64e6985-lyric-forge-ktv`，基于 `main@beb52f1`。
- 该分支包含 Phase 3.1（六个校对入口合成一个「校对」菜单）+ §4.5 的「保存并返回」修复；工作区在提交后应为 clean。
- 已合并：`fb99f4f`（Phase 0 工具，PR #274）、`f54f292`（R2 融合重复行，PR #275）、`f2d2f63`（上传用例 flake，PR #276）、`bade954`（整首一次识别 + 分片 metadata + 检查点指纹，PR #277）、`037a431`（Phase 1.5 降级，PR #278）、`dea805b`（R8 置信度语义，PR #279）、`beb52f1`（R9 Qwen 解码预算，PR #280）。

## 已改文件

- `lib/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart` — 新增：一个「校对」菜单，菜单项旁边写明各自需要的输入（要/不要参考歌词）。
- `lib/features/lyrics/presentation/widgets/unsaved_lyric_edits_dialog.dart` — 新增：未保存对话框抽成公共函数，返回 `stay`/`discard`/`save` 三态；点遮罩一律视为 `stay`。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart` — 工具栏 6 个按钮 → 1 个菜单；窄屏 AppBar 5 个图标 → 1 个图标菜单（窄屏工具栏不再重复）；`save` 现在先保存再 `pop`。
- `test/features/lyrics/presentation/widgets/lyric_proofread_menu_button_test.dart` — 新增：验收「6 → 1」、策略说明文案、按可用性隐藏、每个菜单项的副作用、紧凑变体、全不可用时不渲染。
- `test/features/lyrics/presentation/widgets/unsaved_lyric_edits_dialog_test.dart` — 新增：三态 + 遮罩点击不丢改动。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — §3.5 标为已处理（含「为什么用菜单而不是合并算法」）、§4.3 与 §4.5 同步。
- `docs/log/entries/2026-11-01-2259-single-proofread-entry.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.13.5）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - `dart format`（本次改动的 Dart 文件）=> 0 changed。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0。
  - 7 个受影响测试文件 => 全通过；`bash scripts/quality_gate.sh --skip-pub-get`（全量）=> 通过。
- `lyric_proofread_menu_button_test.dart` 直接锁验收条件：打开前只有一个控件、六个流程标签都不在屏上；打开后三条策略各带一行说明；`null` 回调的项完全不渲染；每一项都触发它自称的动作；紧凑变体是图标按钮但菜单相同；全不可用时渲染为空而不是一个死按钮。
- `unsaved_lyric_edits_dialog_test.dart` 锁三态决策，并特别锁「点遮罩 = stay」——旧代码对「保存并返回」`pop(false)`，正是「保存了却不返回」的来源。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：生成文件一致 + lint 0 error。
- PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 校对入口（Phase 3.1）的取舍：**只改了入口，没合并算法**。三条路径的输入证据不同（无参考 / 有参考 / 有参考 + 独立校时证据），合并算法属于领域层重写，当前没有语料能证明改写更好（R10）。用户的痛点是「不知道点哪个」，菜单里的两行说明解决的就是这个。
- 解码预算（R9）的取舍：`max_new_tokens` 在上游是**每分片**预算，分片上限 1200 秒（不是旧文档写的 180 秒）。公式 `max(1024, 256 + min(时长,1200)×8)` 最坏 9856。仍然**拿不到**「模型是否真的撞到上限」的硬信号：`/v1/transcribe` 不返回 `finish_reason` 或 token 数，只有 OpenAI 兼容端点才有；因此只记录 `maxNewTokens` 与 `transcriptCoverage` 两个可观测量，不据此报警。
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

1. Phase 3.2/3.3：编辑器工具栏重排（首屏可点控件 ≤8）与复核语义统一（`低置信度 N` / `待复核 N` / `智能复核 N` 三套口径合一），纯 UI，CI 可验收。
2. Phase 1.6 剩下的 Whisper 解码参数与 `--prompt`（R7）需要用 `--baseline --fail-on-regression` 验收，等真实语料。
3. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
4. Phase 2.1 首启动可安装性（R5）：只能在真机验收，需用户配合。
5. 偶发失败：`test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving` 有**两种**表现——`SecureSocket.connect` 阶段 `Broken pipe`，以及这次的 `Expected: contains 'upload_total_timeout'` 只收到裸 408。同一个用例，同一类竞态。此前记录的 `forced_alignment_eval_test.dart` 位置有误。

最后更新：2026-11-01 22:59（Asia/Taipei）
