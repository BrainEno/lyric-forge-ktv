# Lyric proofreading v2：契约核对（T0）

> 审查基线：`main@165db5b5ee12ba6b238a24d6b859095525b562b1`，2026-10-22。
> 本阶段仅核对代码并产出文档；没有修改 Dart 源码，也没有把未来设计误写成已存在的 API。

## 1. 名称映射表（本文术语 → 当前真实名称 → 路径）

| 本文术语 | 当前真实名称 / 状态 | 文件路径与位置 |
|---|---|---|
| `LyricDocument` | 已存在，同名；包含 language、lines、globalOffset、metadata | `lib/features/project/domain/models/lyric_document.dart:62-73` |
| `LyricLine` | 已存在，同名；text、startTime、endTime、isChorus、confidence、可选 id | `lib/features/project/domain/models/lyric_document.dart:1-18` |
| `lineId` | 当前字段实际叫 `LyricLine.id`，类型 `String?`；旧数据可为 null | `lib/features/project/domain/models/lyric_document.dart:9-10, 51-58` |
| 行标识分配 | `LyricManualEditMarkerService.assignMissingLineIds`，用 UUID v4 为缺少 id 的行赋值 | `lib/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart:16-28` |
| 显式人工确认 | `LyricReviewDecisionService` 将确认决策存入 `metadata['lyricReviewDecisions']`，以稳定 id + 当前文本/时间指纹记录；它与手动编辑标记是两套独立数据 | `lib/features/lyrics/domain/services/lyric_review_decision_service.dart:6-34, 36-78, 80-102` |
| `LyricAlignmentService` | 已存在，同名；参考歌词与 ASR 草稿的行级序列对齐，不是新 token 对齐服务 | `lib/features/lyrics/domain/services/lyric_alignment_service.dart:218-254` |
| `ReferenceAlignmentApplier` | 已存在，同名；应用行级参考纠正、可选补行与时间来源记录 | `lib/features/lyrics/domain/services/reference_alignment_applier.dart:142-170` |
| `ReferenceTimelineCompletionService` | 已存在，同名；为参考漏行构建时间补全计划 | `lib/features/lyrics/domain/services/reference_timeline_completion_service.dart:83-95` |
| `LyricReviewPriorityService` | 已存在，同名；对现有行排序并解释复核优先级，不修改文档 | `lib/features/lyrics/domain/services/lyric_review_priority_service.dart:31-53` |
| `LyricTimelineValidator` | 已存在，同名；检查时间轴并比较应用前后的新问题 | `lib/features/lyrics/domain/services/lyric_timeline_validator.dart:115-137, 302-320` |
| `ReferenceLyricInput` | 已存在，同名；包含参考行、格式、时间戳、偏移、来源及导入冲突/警告 | `lib/features/lyrics/domain/models/reference_lyric_input.dart:7-35` |
| `HighQualityTranscriptionService` | 已存在，同名；合并 Qwen 与 Whisper 结果并写入 fallback 候选 | `lib/features/transcription/data/services/high_quality_transcription_service.dart:8-21, 117-138` |
| `fallbackCandidates` | 已存在的文档 metadata 键；被复核优先级服务读取 | `lib/features/transcription/data/services/high_quality_transcription_service.dart:123-138`；`lib/features/lyrics/domain/services/lyric_review_priority_service.dart:139-145` |
| `timingProvenance` | 当前按 `lineId -> enum.name` 存在文档 metadata；由参考对齐溯源构建器写入 | `lib/features/lyrics/domain/models/timing_provenance.dart:5-34`；`lib/features/lyrics/domain/services/reference_alignment_provenance_builder.dart:98-115` |
| `LyricSourceStrategy` | 尚不存在；应作为 v2 新增纯 Dart 策略类型 | 计划目录：`lib/features/lyrics/domain/proofreading/` |
| `TimeSource` | 尚不存在同义类型。现有 `LyricTimingProvenance` 是**行级参考对齐时间来源**，不可当作 token 级来源直接复用 | 现有近似概念：`lib/features/lyrics/domain/models/timing_provenance.dart:5-22`；新类型计划放入 `lib/features/lyrics/domain/proofreading/` |
| `TimedToken` | 尚无可供 domain 使用的公开类型。Qwen 适配器里有私有 `_TimedToken`，但仅用于解析 sidecar 响应，且没有新契约要求的 `norm` / `timeSource` | `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart:885-902`；新类型计划放入 `lib/features/lyrics/domain/proofreading/` |
| `TimeInterval`、`LineVerdict`、`VerdictLevel`、`ReasonCode` | 当前未发现匹配的现有类型；按 v2 契约新增，不要借用时间轴 validator 的 UI 文案类型 | 计划目录：`lib/features/lyrics/domain/proofreading/` |
| `ProofreadResult`、`DroppedLine`、`AdlibSuggestion` | 当前未发现匹配类型；按“只产出提议、不落盘”的 v2 契约新增 | 计划目录：`lib/features/lyrics/domain/proofreading/` |
| `LyricTokenizer`、`ReferenceTextSanitizer`、`ProofreadConstants` | 当前未发现匹配实现；属于 T1 新文件 | `lib/features/lyrics/domain/proofreading/proofread_constants.dart`；`lyric_tokenizer.dart`；`reference_text_sanitizer.dart` |

## 2. Q1–Q8：现状证据与结论

### Q1. 转写后词级时间是否保留？存在哪里？

**结论：词级时间会被读取并用于分行，但不会以结构化 token 列表保存在最终的 `LyricDocument` 中。** Qwen 路径把 `timestamps.items` 等兼容形态解析为私有 `_TimedToken`，随后按停顿、时长和文本长度等规则合并为 `LyricLine`；新行只保留聚合后的 `startTime` / `endTime` / text / confidence。完整响应同时写入输出目录中的 `qwen3_asr_result.json`，文档 metadata 存 `rawJsonPath`，`TranscriptionResult` 也暴露该路径及 `normalizedAudioPath`。因此 v2 若要使用词级证据，必须设计明确的数据入口；不能假设 `LyricDocument.lines` 已包含 token 时间。

证据：`lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart:61-62, 96-99, 133-160, 180-200, 587-612, 641-653, 675-710`；`lib/features/transcription/domain/models/transcription_models.dart:245-282`。

### Q2. ForcedAligner 能否对任意文本调用？入参、出参、语言参数、单次时长上限是什么？

**结论：当前应用调用路径不能把任意参考文本传给 ForcedAligner。** 当前启动本地 sidecar 时通过 `--forced-aligner <model>` 指定模型，但请求 `POST /v1/transcribe` 的 body 是音频路径、`return_timestamps: true`、生成/批处理选项，以及可选 context 和 language；没有 `text` / transcript 参数。这里的 `context` 是提示上下文，不能据此认定为“强制对齐指定参考文本”。sidecar 也可能有其他接口，但当前仓库没有调用或验证它们，所以按现有合同应视为“尚不能传任意文本”。

- 请求：`audio`、`return_timestamps`、`max_new_tokens`（按标准化音频时长推导，见 `lib/features/transcription/domain/models/qwen_decode_budget.dart`）、`max_batch_size`、`bucket_by_length`，可选 `context` 与 `language`。
- 语言：配置值 `zh/en/ja/ko` 分别映射为 `Chinese/English/Japanese/Korean`；其他值会省略 language，交由运行时自动检测。源码路径：`lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart:480-484`。
- 响应：优先解包 `results[0]`；接受 segment 形态以及 `words`、`time_stamps`、`timestamps.word(s/items/list)` 等形态。时间项可用 `text/word` 和 `start/start_time/begin`、`end/end_time/finish` 字段。源码路径：`lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart:463-478, 565-612, 617-653`。
- 时长：应用层把整首标准化音频一次提交，当前没有由 Dart 请求器强制的单次秒数上限。仓库文档描述的被评估 Rust/Candle sidecar 会把长音频内部切成**每段不超过 1200 秒**（`MAX_ASR_INPUT_SECONDS`）的块并修正回全曲时间轴；这是当前参考实现的内部行为，不应误写成所有未来 adapter 的通用保证。证据：`docs/high_quality_asr.md`「Qwen native runtime contract」小节。

### Q3. vocal stem 路径从哪里取？没有分离时怎么办？

**结论：** 转写编排从项目的 `ProjectManifest.audioAsset` 读取候选路径，优先选择存在的 `AudioAsset.vocalPath`，其次 `normalizedPath`，最后 `originalPath`；三个路径都不可用时才报输入错误。Qwen/Whisper adapter 各自把选定输入经 FFmpeg 转成 16 kHz 单声道 PCM WAV。项目文档明确指出最终本地人声/伴奏分离后端尚未完成，所以当前不能保证存在 vocal stem。

证据：`lib/features/transcription/data/services/local_project_transcription_workflow.dart:233-249`；`lib/features/project/domain/models/audio_asset.dart:1-24, 67-81`；`lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart:61-73, 214-250`；`lib/features/transcription/data/services/whisper_cpp_transcription_service.dart:40-49, 132-168`；`docs/high_quality_asr.md:221-229`。

### Q4. LyricLine 是否有稳定 lineId？新行的 id 谁生成？

**结论：有可选稳定 ID，但真实字段名是 `LyricLine.id`，并非 `lineId`；旧数据可以为 null。** `LyricManualEditMarkerService.assignMissingLineIds` 只给缺失 id 的行生成 UUID v4，保持已存在 id 不变；编辑器加载和参考对齐补入新行时会补齐缺失 ID。纯文本/ASR 行在所有创建路径中是否立即带 id 不能假设为是，因此 proofread pipeline 仍须处理 null ID，并确保最终输出行 ID 唯一。

证据：`lib/features/project/domain/models/lyric_document.dart:1-18, 51-58`；`lib/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart:16-28`；`lib/features/lyrics/presentation/screens/lyric_editor_screen.dart:441-444`。

### Q5. 用户手动编辑过的行如何表示？

**结论：** 手动编辑标记由编辑器会话的 `Set<String> _manuallyEditedLineIds` 维护，保存到文档 metadata 的 `manuallyEditedLineIds` 键，重开时恢复；`protectedIndices` 按稳定 ID 派生出当前行索引，供参考对齐应用器跳过这些行。显式复核确认另有独立的 `LyricReviewDecisionService`，写入 `metadata['lyricReviewDecisions']`，按稳定 ID 保存 `fingerprint` 与 `reviewedAt`，并在文本或起止时间改变后自动失效。v2 将“编辑过”和“显式确认过”的保护条件合并时，必须读取两套记录并按当前行 ID 归一化，不能只看 `manuallyEditedLineIds`。证据：`lib/features/lyrics/presentation/screens/lyric_editor_screen.dart:98-102, 137-142, 312-315, 408-417`；`lib/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart:13-14, 34-49, 60-68`；`lib/features/lyrics/domain/services/lyric_review_decision_service.dart:6-34, 36-78, 80-102`；`lib/features/lyrics/domain/services/reference_alignment_applier.dart:160-170, 226-229`。

**必须处理的语义偏差：** 当前参考对齐界面有一个显式覆盖手工编辑行的用户选择（`overriddenAsrLineIndices`）。v2 新契约要求受保护行的文字与时间永不被流水线修改；新 proofread 流水线不得继承这条覆盖路径，也不能复制保护行来绕过保护。

### Q6. timingProvenance 的取值和存放位置是什么？

**结论：** 当前枚举 `LyricTimingProvenance` 值为 `reference`、`mappedAsr`、`interpolated`、`estimatedTail`、`autoRepaired`、`manual`。持久化键是 `metadata['timingProvenance']`，其值按稳定 `lineId` 映射到枚举的 `.name`。现有语义描述的是行级参考对齐采用/推断/修复的时间来源，不等于草案里的 token 级 `TimeSource`（`asrWord/aligner/anchorInterpolated/userLocked`）。

证据：`lib/features/lyrics/domain/models/timing_provenance.dart:5-34`；`lib/features/lyrics/domain/services/reference_alignment_provenance_builder.dart:98-115`。

### Q7. whisper 调用是否已关闭“上文条件”？

**源码层面结论：未显式关闭。** `WhisperCppTranscriptionService._runWhisper` 当前传入 `-m`、`-f`、`-l`、`-ojf`、`-of`、`-pp`，未传入 `-mc 0` 或 `--max-context 0`。但是，要求以**实际配置的 whisper.cpp 二进制的 `--help`** 核实参数拼写与默认行为；此执行环境没有本地 checkout，也没有 Dart/Flutter 和配置的 whisper 可执行文件，因此不能验证当前安装二进制的 help。严格答案是：**adapter 目前没有显式禁用；二进制的选项/默认行为未知，不能推断。**

证据：`lib/features/transcription/data/services/whisper_cpp_transcription_service.dart:170-192`。待验证命令应在目标部署机器对配置中的 whisper 可执行文件运行 `--help`，确认后再决定是否加参数。

### Q8. 当前 `flutter test test/features/lyrics` 基线如何？

**仓库最近一次可追溯记录：215/215 通过；全量 `flutter test` 记录为 549/549 通过。** 记录在 `docs/handoff.md:29-34` 和 `docs/log/entries/2026-10-22-0240-bounded-lyric-line-audition.md`。本次执行环境无法重新跑测试，因此这属于最近的存档基线，不是本次运行结果。主分支当前审查基线是上述 commit；不要把更早 E5 记录的 179/179 或 513 个全量通过数当作最新数字。

## 3. 第 3 节设计摘要与约束

### Pipeline

输入为草稿文档、可选参考歌词、策略、受保护行，以及可选强制对齐器/人声活动/声学打分器端口。流水线只生成 `ProofreadResult` 提议，不落盘；用户应用时复用现有备份与撤销流程。

- **referenceFirst：** 清洗参考歌词，以 token 锚点对齐；优先用强制对齐器给参考 token 定时，没有对齐器时才用锚点与插值，并把估算时间标为需复核；最终以参考行重建文档。
- **asrFirst：** 识别与多引擎共识优先；重新分行、重复段自校正、幻觉过滤；参考歌词只能作为纠错建议，除非有音频证据，否则不能自动覆盖 ASR 文本；改动行需要重新定时。
- **auto：** 无参考歌词时走 asrFirst；有参考歌词时先算 token 对齐的 referenceCoverage。coverage ≥ 0.25 走 referenceFirst，否则退回 asrFirst，并把 `autoFellBackToAsr` 和覆盖率写入 notes。UI 必须说明低重合可能是 ASR 较差，且始终允许用户手动切换。

### Verdict 与应用

- `locked`：用户编辑/确认的受保护行，文字和时间保持输入值。
- `green`：证据足够，可批量一键应用。
- `amber`：存疑，进入按 risk 降序排列的复核队列。
- `grey`：疑似幻觉/未演唱，不进入 proposed 文档，但可通过 dropped 恢复。

### 必须守住的不变量

- I1：行开始时间非递减，且前一行 end ≤ 后一行 start。
- I2：普通输出行时长至少 0.30 秒；受保护行例外。
- I3：referenceFirst 中每条参考行最多出现一次；不能留下文本相似度 ≥ 0.9 且时间重叠的相邻重复行。
- I4：受保护行的 text/start/end 与输入完全一致。
- I5：执行前后深比较输入文档相等，不原地修改参数。
- I6：正常输出时间非负且不越过已知音频边界；ASR-first 为避免静默改写源时间，若输入区间越界，必须显式标记 `timingConflict` 并保持琥珀色复核，不得被当作安全结果。
- I7：每条输出行都有 verdict，lineId 不重复。
- T7a、T7b 流水线测试中必须调用同一个 `expectInvariants` 辅助函数。

非目标仍是在线搜索、CTC 声学打分、LLM 融合；相关能力留到 T10 接口，不放进本轮。

## 4. 后续任务清单（T1–T9）

> T1 的范围来自本任务说明的完整规格。T2–T9 是按上文目标与流水线拆出来的建议工作边界；在进入各任务时仍需检查真实调用点，不凭空新增接口。

- [x] **T1 — 分词器、参考歌词清洗与常量。** 精确新增 `proofread_constants.dart`、`lyric_tokenizer.dart`、`reference_text_sanitizer.dart` 和两份对应 domain 单测。按任务原文逐字覆盖分词与 sanitizer 测试样例；先写测试再实现。不引入依赖，不用 Unicode 正则属性类。
- [x] **T2a — 有界 token 序列对齐。** 纯 Dart Needleman–Wunsch token 匹配与 `referenceCoverage`；对 DP cells 强制上限，超限时不分配矩阵。
- [ ] **T2b — 唯一锚点与重复段消歧。** 实现已随 PR #139 进入 main；仍需在本地验证唯一 n-gram 候选、有界候选数、单调非重叠锚点链和 DP 回退。高重复窗口不能作为唯一锚点。
- [x] **T3 — 策略选择。** 实现 `referenceFirst/asrFirst/auto` 的纯领域编排，严格遵守 coverage 0.25 的自动选择规则和 fallback notes。
- [ ] **T4 — referenceFirst 流水线。** 实现已随 PR #140 进入 main；本环境未重新运行本地测试，完成状态待验证。清洗参考文本、token 锚点对齐、参考时间分配、按参考行重建；插值与低证据时间必须给出琥珀色 verdict。
- [ ] **T5 — asrFirst 流水线。** PR #141 共识分析、#143 幻觉候选、#144 重复片段移植、#145 参考纠错建议已进入 `main`（本环境未重跑本地验证）。Draft PR #146 新增安全重定时提案：只接受附近第二 ASR 的精确文本/时间匹配；多重匹配、低置信度、邻行冲突或音频越界均不得作为可用时间。未匹配时不按文本长度猜时间；不自动应用。重新分行及 ForcedAligner 任意文本适配仍待实现。
- [ ] **T6 — 证据与结果合同。** 实现 TimedToken/TimeInterval/verdict/reasons/risk/dropped/adlibs/ProofreadResult；domain 只返回枚举/原因码，不放中文 UI 文案。
- [x] **T7 — 两条流水线不变量测试。** 为 T7a、T7b 写测试并调用同一 `expectInvariants`，覆盖 I1–I7、保护行、输入不变性、重复行、音频边界与缺失时长情形。
- [x] **T8 — UI 接入。** 策略开关、摘要、仅琥珀色复核、绿色一键应用与 grey 行恢复；只使用已有备份/撤销流程，不从 presentation 直接访问数据库、Process 或新增磁盘写入路径。
- [ ] **T9 — 回归与交付。** 运行 format、analyze、定向测试、`flutter test test/features/lyrics`、work-log write/check；按 AGENTS.md 记录完成条目、更新 handoff，并提交独立 PR。
