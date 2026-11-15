# 歌词质量基线（Phase 0）

> 目的：在改动识别管线之前，先让「变好 / 变差」变成可测量的数字。
> 工具：`tool/asr_quality_report.dart`（纯 Dart，无需模型、无需音频、秒级完成）。

## 1. 为什么需要它

现有两个评估工具各缺一半：

| 工具 | 能测 | 不能测 |
|---|---|---|
| `tool/asr_transcript_eval.dart` | 整段文本的 CER / WER | 断行、重复行、时间戳（其 `interpretation.limitations` 明确写了这点） |
| `tool/forced_alignment_eval.dart` | 已有人工标注的时间点 | 识别文本本身的断行质量 |
| **`tool/asr_quality_report.dart`** | **行召回、CER、重复行率、时间戳误差** | 音频域问题（音质、人声分离、速度） |

用户感知到的「不如以前」，恰恰落在前两者的空隙里：**多出来的重复行**（双引擎融合引入）和**断句错乱**。整段 CER 对这两件事几乎无感——插入 20 行重复歌词，CER 可能只上升几个百分点，但用户看到的是一屏垃圾。

## 2. 三分钟上手

```bash
# 1) 建语料目录（已被 .gitignore 忽略，不会进仓库）
mkdir -p corpus/song-01

# 2) 放三份东西
#    corpus/song-01/reference.lrc    人工校对过的正确歌词（基准）
#    corpus/song-01/whisper.lrc      只跑 Whisper 的输出
#    corpus/song-01/fused.lrc        最高质量（双引擎融合）的输出

# 3) 写 corpus/corpus.json（见第 3 节）

# 4) 跑
dart run tool/asr_quality_report.dart --corpus corpus/corpus.json \
  --output corpus/baseline-2026-11.json
```

输出示例（仓库内 CLI 冒烟测试的真实输出，3 行参考 + 4 行融合输出；生成于 #448 之前，当前版本的表格在 CER 后多一列 `WER`，见第 10 节）：

```
# Lyric quality baseline

1 song(s), 1 candidate document(s), match threshold 0.6.

## By engine

| engine | songs | recall | precision | CER | duplicate rate | line ratio | start MAE | within 500 ms |
|---|---|---|---|---|---|---|---|---|
| fused | 1 | 100.0% | 75.0% | 11.3% | 25.0% | 1.33 | 100 ms | 100.0% |

## Duplicate lines

- song-01 / fused (contained, t=10000 ms): "we are dancing through the night"
```

读法：行召回 100% 说明没漏词，但**精确率只有 75%、重复行率 25%、行数比 1.33** —— 4 行里有 1 行是从第 1 行里拆出来的 "dancing"。这正是「识别得没错，但输出是脏的」的量化形态。

## 3. 语料格式

`corpus/corpus.json`：

```json
{
  "schemaVersion": 1,
  "matchThreshold": 0.6,
  "songs": [
    {
      "id": "song-01",
      "language": "zh",
      "reference": { "path": "song-01/reference.lrc", "reviewed": true },
      "candidates": [
        { "engine": "whisper", "path": "song-01/whisper.lrc" },
        { "engine": "qwen", "path": "song-01/qwen.lrc" },
        { "engine": "fused", "path": "song-01/fused.lrc" }
      ]
    }
  ]
}
```

要点：

- `path` 相对 `corpus.json` 所在目录解析。
- `reference.reviewed` 必须显式写 `true`。不写会在报告里产生警告——**只有人工校对过的参考歌词才能当基线**，否则你测到的是「两段自动结果的差异」。
- 每个候选可以写 `path`（文件）、`text`（内联 LRC 文本）或 `lines`（内联行数组），见第 6 节。
- 同一首歌里 `engine` 不能重复；不同歌可以用同名 engine，报告会自动按 engine 聚合。

## 4. 四个核心指标

| 指标 | 定义 | 理想值 | 说明 |
|---|---|---|---|
| **行召回 `lineRecall`** | 参考行中能匹配上某个输出行的比例（相似度 ≥ 阈值） | ≥ 0.95 | 低 = **漏歌词** |
| **CER `normalizedCharacterErrorRate`** | 整篇字符编辑距离 / 参考字符数（与 `asr_transcript_eval.dart` 同口径） | ≤ 0.10 | 低 = **字错得少** |
| **重复行率 `duplicateLineRate`** | 时间上重叠（含嵌套）、且文本被另一行包含或几乎相同的「多余行」/ 输出行数 | ≤ 0.02 | 高 = **融合在灌水** |
| **时间戳误差 `startTimeMaeMs`** | 已匹配行对上，起始时间绝对误差的均值 | ≤ 300 ms | 高 = **字幕对不上口型** |

配套指标：`linePrecision`（输出里有多少行是真歌词）、`lineCountRatio`（输出行 / 参考行，>1.2 说明在插入行）、`within500msRate`（±500 ms 命中率）。

**行匹配是保序的**：参考与输出按顺序做序列对齐（DP，最大化相似度之和），所以重复的副歌不会匹配错位置，一行长句也不会吞掉几行短句。

**重复行的判定必须带时间条件**，否则会把正常的副歌重复也算成缺陷。两行必须「发生在同一时刻」，满足任一即可：

- 起始时间相差 ≤ 1500 ms；或
- 一行的**时间区间**有 ≥80% 落在另一行区间内（嵌套）。

并且文本上是同一句：一行是另一行的子串（≥90 字符合同），或两行相似度 ≥ 0.85。

**为什么要看时间区间而不只是起始时间**：一句跨 12 秒的长行里，碎片可能从第 3 秒才开始。只比起始时间会完全漏掉这种嵌套重复——而这正是双引擎融合最容易产生的形态。

隔一分钟重复的副歌两种条件都不满足（不重叠），所以不会被误判。没有时间戳时，只比较相邻行（融合重复总是紧贴父行出现，副歌重复不会）。

## 5. 基线对比（Phase 1 的验收手段）

```bash
# 改动前：存一份基线
dart run tool/asr_quality_report.dart --corpus corpus/corpus.json \
  --output corpus/baseline.json

# 改动后：对比，并在退化时让命令失败（可接进 CI 或本地脚本）
dart run tool/asr_quality_report.dart --corpus corpus/corpus.json \
  --baseline corpus/baseline.json --fail-on-regression
```

判定阈值（写死在工具里，改动需要连带改测试）：

| 指标 | 视为退化的条件 |
|---|---|
| `lineRecall` | 下降 > 2 个百分点 |
| `normalizedCharacterErrorRate` | 上升 > 2 个百分点 |
| `duplicateLineRate` | 上升 > 2 个百分点 |
| `lineCountRatio` | 上升 > 0.05 |
| `startTimeMaeMs` | 上升 > 50 ms |

这正是判定 Phase 1 修复是否成功的依据：

- **1.2 融合匹配重写** → `duplicateLineRate` 从 >30% 降到 <2%，且 `lineRecall` 不下降（不能靠「删掉次要引擎的所有行」来刷指标）。
- **1.1 取消全局 3 分钟分片** → 接缝处的重复行归零，`lineCountRatio` 回落到 1.0 附近。（已落地：阈值 20 分钟，歌曲整首一次；见 `docs/local_transcription.md`。）
- **1.6 Whisper 参数** → `CER` 下降、`lineRecall` 上升。

> **反作弊提示**：单独看任何一个指标都能被刷。必须同时满足「重复行率下降 + 行召回不降」，才算真的修好了融合。

## 6. 单曲快速对比（不写语料）

只想看一首歌，不需要 JSON：

```bash
dart run tool/asr_quality_report.dart \
  --reference corpus/song-01/reference.lrc \
  --hypothesis corpus/song-01/fused.lrc \
  --engine fused --json
```

`--engine` 只是报告里的标签，默认 `hypothesis`。

## 7. 输入从哪来

| 来源 | 怎么拿 | 备注 |
|---|---|---|
| 参考歌词（基准） | 自己对着歌曲听一遍，在编辑器里改到正确后**导出 LRC** | 也可以用现成的带时间歌词（注意版权，别提交进仓库） |
| 应用输出 | 编辑器导出 LRC | 或直接用 `projects.json` 里的 `lyricDocument` |
| 分引擎输出 | 单独跑一次「Whisper 单模型」，导出；再切「最高质量」导出 | 两次用同一首歌、同一段音频 |

支持的文件格式会自动识别：

- **`.lrc`** —— `[mm:ss.xx]`、`[mm:ss.xxx]`、`[mm:ss]`；一行多个时间戳会展开成多行；`[ti:]`/`[ar:]` 等元数据自动忽略。
- **`.txt`** —— 每行一句，无时间戳（此时时间戳指标为 null，报告会警告）。
- **`.json`** —— `LyricDocument`（`{language, lines:[{text,startTime,endTime}]}`）、裸行数组、或整个 `projects.json` 导出（会自动展开其中的 `lyricDocument`；多于一个工程时会报错，请先拆分）。

## 8. 造一份合格语料的建议

目标是 **5–10 首**，覆盖：

- 语种：中文（含长短句）、英文、日文各至少 1 首；中英混杂 1 首。
- 速度：慢歌 1 首（长句多，最容易断句错）、快歌/Rap 1 首（最容易漏行）。
- 结构：有明显副歌重复的 1 首（用来确认重复行判定不会误报）、有和声/垫音的 1 首（最容易产生幻听行）。
- 时长：**必须有一首 ≥ 4 分钟**（旧版本在这里会切出接缝；现在应整首一次识别。保留这首是为了防止分片阈值被改回去）。

校对标准：**逐行确认文本与时间**，允许保留明显的语气词；不确定的地方宁愿标「不确定」也不要猜——基线里的错误会被当成正确答案，后面所有对比都会被污染。

## 9. 已知限制

- 只评估文本、断行与时间戳；不评估音质、人声分离、速度、显存占用。
- 时间戳指标要求参考与输出**双方都有时间戳**；参考是纯文本时只会得到文本类指标。
- 行匹配阈值默认 0.6，对「一行被切成两半」这类情况偏宽松（半句相似度可能低于阈值 → 反而算漏行）。调整用 `--match-threshold`，但**一旦改变阈值，旧的基线报告不可直接比较**。
- 单个文档最多 300 行（超过请先拆分歌曲），这是为了避免 DP 对齐爆炸。
- 报告不含生成时间，便于直接 diff；版本号在 `schemaVersion` 与 `evaluator` 字段里。

### Fusion timing evidence (experimental, not a quality gate)

Successful two-engine fusion records a `fusionTimingEvidence` v1 snapshot for
output rows: SHA-256 of the exact UTF-8 final text and the text returned with
the retained source timing, a primary-text-changed flag, and a fusion-specific
`needsRealignment` flag for changed or secondary-only rows. This is diagnostic
metadata only: existing timestamps, model selection and application policy are
unchanged. Hashes of short lyrics can be guessed and should be treated as
sensitive content, not anonymization.

The returned timed text is **not necessarily the actual ForcedAligner input**;
therefore `alignedTextHash` is null until such input is independently captured.
Unchanged text and `needsRealignment: false` do not verify audio identity, model
version, alignment quality, completeness, or playback readiness. Older or
single-engine/degraded results may have no evidence and must be treated as
unknown. No automatic re-alignment or playback certification is implemented.

Evidence is indexed by the output row and is a snapshot, not a live editor
state. Consumers must use `FusionTimingEvidence.forLine` or
`validatedEntries` to reject malformed, duplicate, text-changed, retimed or
reordered entries; missing data is unknown. Text and line times alone cannot
establish that the audio or model is unchanged. Chunk merging keeps the
snapshot associated with the selected overlap row, converts its times to the
song clock, and leaves a row unknown if its selected checkpoint lacks evidence.
The source/model/audio and preprocessing identity needed for future re-alignment
must be verified separately before applying any suggestions.

## 10. WER 与「仅副引擎行」指标（#448）

#448 在同一工具里增加了三个指标，schema 仍为 v1，全部是新增键，旧报告可以继续读，旧的对比命令也能继续用。

| 指标 | 定义 | 看什么 |
|---|---|---|
| **WER `normalizedWordErrorRate`** | 整篇词级编辑距离除以参考词数。文本先小写，全角折叠为半角，标点替换为空格。拉丁文字按空白和标点切词，词内撇号保留；汉字、假名、谚文每个字算一个词，**所以纯中文或日文歌曲 WER 等于 CER**。 | 英文歌的字错。CER 会被长单词稀释，WER 更接近听感。 |
| **`secondaryOnlyPrecision`** | 融合结果里带「仅副引擎」标记的行中，能匹配到参考行的比例。另报 `secondaryOnlyLineCount`、`secondaryOnlyMatchedCount`、`secondaryOnlyUnmatchedCount`。 | 「建议补入」候选里有多少是真歌词。剩下的多是和声、ad-lib 或幻听，需要用户拒绝。 |
| **`secondaryRetention.retentionRate`** | 先找出参考行中被副引擎匹配到、但主引擎没有匹配到的行（`secondaryOnlyReferenceLineCount`），再算其中仍被融合结果匹配到的比例。`retainedAsSuggestionCount` 统计保留下来、并且以「建议补入」标记呈现的行数。`droppedReferenceLines` 列出被丢掉的行。 | **低于 1.0 就说明融合静默丢掉了一句只有副引擎听到的正确歌词。** 这是 #448 的否决项，应当始终为 1.0。 |

「仅副引擎」标记的来源，依次为：

1. 每行的 `secondaryOnly: true`；
2. `LyricDocument.metadata.secondaryOnlySuggestions`（v1，按 `start|end|text` 精确匹配）；
3. 旧版 `metadata.secondaryOnlyLineIndices`（越界或非整数的索引会被忽略）。

### 语料中声明 retention

```json
{
  "id": "song-01",
  "reference": { "path": "song-01/reference.lrc", "reviewed": true },
  "candidates": [
    { "engine": "qwen-only", "path": "song-01/qwen.json" },
    { "engine": "whisper-only", "path": "song-01/whisper.json" },
    { "engine": "fused", "path": "song-01/fused.json" }
  ],
  "secondaryRetention": { "primary": "qwen-only", "secondary": "whisper-only", "fused": "fused" }
}
```

三个名字都必须是本曲已有的 candidate，否则工具报 `FormatException`。报告顶层的 `secondaryRetention` 汇总所有声明了 retention 的歌曲；没有任何一首声明时，不输出这个键。

### 仓库内的确定性夹具

`test/fixtures/asr_quality/{en,zh,ja}/` 下是**为本仓库原创的**歌词文本，以及手写的两引擎输出，不含音频，也不是模型的真实输出。`test/tool/asr_fusion_fixture_eval_test.dart` 把这些输出喂给生产代码 `HighQualityTranscriptionService`，再用本工具打分。夹具覆盖了以下情况：

- 主引擎漏行（只有 Whisper 识别到的真歌词）；
- 断句不同（Whisper 把相邻两行切成三段）；
- 重复副歌；
- 与已有行重叠的短 ad-lib。

这个测试只使用基线已有的 API，所以可以原样复制到基线 checkout 里跑出「改动前」的报告。环境变量：

- `LYRIC_FUSION_EVAL_OUT=path.json`：写出 JSON 和同名的 `.md`；
- `LYRIC_FUSION_EVAL_BASELINE=1`：只出报告，不做断言。

这些数字衡量的是**融合逻辑**，而不是模型识别能力。真实模型的前后对比要按 `docs/high_quality_asr_windows_setup.md` 的「#448 手工验证」一节在 Windows 上跑。
