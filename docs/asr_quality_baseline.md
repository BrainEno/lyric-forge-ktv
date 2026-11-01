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

输出示例：

```
# Lyric quality baseline

1 song(s), 3 candidate document(s), match threshold 0.6.

## By engine

| engine | songs | recall | precision | CER | duplicate rate | line ratio | start MAE | within 500 ms |
|---|---|---|---|---|---|---|---|---|
| fused | 1 | 100.0% | 58.3% | 9.2% | 41.7% | 1.71 | 240 ms | 88.0% |
| qwen | 1 | 82.1% | 95.0% | 18.4% | 5.0% | 0.86 | 610 ms | 52.0% |
| whisper | 1 | 94.3% | 93.1% | 11.7% | 0.0% | 1.01 | 380 ms | 71.0% |

## Duplicate lines

- song-01 / fused (contained, t=41200 ms): "we are dancing through the night"
```

一眼就能读出结论：**融合（fused）把行召回从 94% 拉到 100%，代价是重复行率 0% → 42%、行数比 1.01 → 1.71。** 这就是「不如以前」的量化形态。

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
| **重复行率 `duplicateLineRate`** | 时间上挨在一起、且文本被另一行包含或几乎相同的「多余行」/ 输出行数 | ≤ 0.02 | 高 = **融合在灌水** |
| **时间戳误差 `startTimeMaeMs`** | 已匹配行对上，起始时间绝对误差的均值 | ≤ 300 ms | 高 = **字幕对不上口型** |

配套指标：`linePrecision`（输出里有多少行是真歌词）、`lineCountRatio`（输出行 / 参考行，>1.2 说明在插入行）、`within500msRate`（±500 ms 命中率）。

**行匹配是保序的**：参考与输出按顺序做序列对齐（DP，最大化相似度之和），所以重复的副歌不会匹配错位置，一行长句也不会吞掉几行短句。

**重复行的判定必须带时间条件**，否则会把正常的副歌重复也算成缺陷：

- 两行起始时间相差 ≤ 1500 ms，**且**
- 一行是另一行的子串（≥90%），或两行字符相似度 ≥ 0.85。

隔一分钟重复的副歌不算重复行。没有时间戳时，只比较相邻行（融合重复总是紧贴父行出现，副歌重复不会）。

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
- **1.1 取消全局 3 分钟分片** → 接缝处的重复行归零，`lineCountRatio` 回落到 1.0 附近。
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
- 时长：**必须有一首 ≥ 4 分钟**（这是当前全局 3 分钟分片的接缝所在，R1 的回归最容易在这里暴露）。

校对标准：**逐行确认文本与时间**，允许保留明显的语气词；不确定的地方宁愿标「不确定」也不要猜——基线里的错误会被当成正确答案，后面所有对比都会被污染。

## 9. 已知限制

- 只评估文本、断行与时间戳；不评估音质、人声分离、速度、显存占用。
- 时间戳指标要求参考与输出**双方都有时间戳**；参考是纯文本时只会得到文本类指标。
- 行匹配阈值默认 0.6，对「一行被切成两半」这类情况偏宽松（半句相似度可能低于阈值 → 反而算漏行）。调整用 `--match-threshold`，但**一旦改变阈值，旧的基线报告不可直接比较**。
- 单个文档最多 300 行（超过请先拆分歌曲），这是为了避免 DP 对齐爆炸。
- 报告不含生成时间，便于直接 diff；版本号在 `schemaVersion` 与 `evaluator` 字段里。
