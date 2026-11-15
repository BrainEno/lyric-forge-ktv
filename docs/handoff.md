# Handoff

## 目标

修复 #448：导入歌曲后歌词更完整，错误能被快速发现，用户可以试听，再在现有复核流程里接受或拒绝。PR 标题固定为 `[model-eval] Improve lyric ASR recall and proofreading workflow`。不自行合并，等统一评审。

## Git 现场

- 分支：`arena/90ba1ce5-lyric-forge-ktv`，基于 main `0e93b6569b46b2a5b06de480c1d5661666e7026c`。
- 验证用的临时 workflow `tmp-arena-448-validate.yml`、`.github/tmp_report.py`、`tool/.tmp_ci_*` 在开 PR 前删除，不进入 PR diff。
- `docs/benchmarks/2026-11-14-fusion-fixtures-*` 由临时 workflow 生成并提交：基线 `0e93b65` 与当前代码用同一份夹具输入各跑一次。

## 已改文件

- **识别**
  - `whisper_decoding_policy.dart`（domain）：两个 profile，standard 与 lyrics。
    - 提示词只来自 `RecognitionHints`（歌名、歌手、专辑、用户专有名词）；这个类型没有歌词字段。
    - 提示词按语言模板生成、清洗，并限制在 200 UTF-8 字节以内。
    - 根据 `-h` 输出判断运行时能力，只使用运行时实际列出的参数（`--prompt`、`--suppress-nst`）。
  - `whisper_cpp_transcription_service.dart`：
    - 能力缓存按 `path|size|mtime`。
    - Windows 下非 ASCII 提示词通过 UTF-8 `@file` 传递。
    - 运行时拒绝参数时，用标准参数重试一次。
    - 去除提示词回声行。
    - 解码计划（不含提示词原文）写入 `metadata.whisperDecoding`。
  - `resumable_chunked_transcription_service.dart`：指纹包含 profile 和提示；`secondaryOnlySuggestions` 跨分片平移、合并。
  - `high_quality_transcription_service.dart`：
    - 仅断句不同的副引擎行只计数，不插入。
    - 其余仅副引擎行作为「建议补入」插入，并在 `secondaryOnlySuggestions` 中精确记录。
- **编辑器**
  - `recognition_review_summary.dart` 与 `lyric_recognition_summary_card.dart`：摘要卡默认折叠，位于列表栏内部。
  - inspector 的 `SecondarySuggestionCard`：试听、保留、拒绝。
  - controller 在插入、删除行时平移带索引的复核 metadata。
- **证据**
  - `tool/asr_quality_report.dart`：新增 WER、`secondaryOnlyPrecision`、`secondaryRetention`。
  - EN/ZH/JA 原创夹具，以及 `test/tool/asr_fusion_fixture_eval_test.dart`。
- **文档**：`asr_quality_baseline.md` 第 10 节；`local_transcription.md`；`high_quality_asr_windows_setup.md`（#448 手工验证步骤和结果模板）；`decisions.md`（D-014）；工作日志条目 `2026-11-15-1045`。

## 检查结果

全部来自 GitHub Actions；沙箱里没有 Dart/Flutter 工具链。每次运行的结果见工作日志条目，全量测试结果见 PR 正文。

夹具上的融合结果（当前对比基线）：

| 指标 | 当前 | 基线 |
|---|---|---|
| 融合输出行数 | 23 | 26 |
| 精确率 | 91.3% | 80.8% |
| CER | 2.8% | 14.8% |
| WER | 3.2% | 18.1% |
| 行召回 | 100% | 100% |
| 仅副引擎行保留 | 4/4 | 4/4 |

## 下一步

- 在 Windows 真机上按 `docs/high_quality_asr_windows_setup.md` 的 #448 一节跑 A/B，填结果模板。
- 根据真实数据决定 lyrics profile 是否继续作为默认值。

## 已知风险

- 提示词在真实模型上的收益没有测量过，可能是零，也可能引入轻微偏置。遇到这种情况可以在设置中关闭「Whisper 歌词增强解码」，恢复到旧的命令行。
- 夹具是手写的，用来覆盖断句、漏行、副歌和 ad-lib；它衡量的是融合逻辑，不代表真实歌曲的分布。
- 切换 profile 会让已有的分片断点失效（这是有意的）。
