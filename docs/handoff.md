# Handoff

## 目标

用户反馈（#467、#468 之后）：歌曲后半段仍会一两句无限重复。查明原因并针对性修复（D-027）：

- **原因**：whisper.cpp 把之前解码的文字作为下一个 30 秒窗口的上下文，循环会自我强化；v1 歌词档位的歌名歌手提示也在同一上下文里。逐行比较的融合看不到跨行循环。
- **预防**：歌词档位改为 `whisper-lyrics-v2`（`--suppress-nst --max-context 0`，不发提示）。6 首 CC 歌曲实测平均词错误率 0.815 → 0.354，没有成组循环。
- **恢复**：首遍保留了文字历史且强循环时，只把循环的一段关闭历史重新识别。
- **仲裁**：融合时用 Qwen 在同一段听到的内容判断循环是真是假，替换、保留或删减并进入复核。

合并前先征求用户确认。

## Git 现场

- 分支：`arena/c21298fd-lyric-forge-ktv`，基于 main `c67b08755f7f0380a57c02b68c358ddd74953e8e`。
- 实验和验证用的临时 workflow 以及它们提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域**：`transcription/domain/services/asr_segment_loop_detector.dart`、`whisper_loop_recovery.dart`、`whisper_loop_arbiter.dart`（新）；`whisper_decoding_policy.dart`（v2 档位、`disablesTextHistory`、循环恢复参数探测）。
- **数据**：`whisper_cpp_transcription_service.dart`（循环段重新识别）、`high_quality_transcription_service.dart`（四条融合路径接入仲裁）、`resumable_chunked_transcription_service.dart`（指纹）。
- **界面**：识别设置开关说明、识别摘要的档位名称。
- **文档**：`decisions.md`（D-027）、`high_quality_asr.md`、`local_transcription.md`、工作日志条目 `2026-11-23-1200`、本文件。

## 检查结果

临时 workflow（run 44056944598）：`flutter analyze` 0 个错误/警告，186 条 info（与 main 相同）；定向测试 220 个通过；全量 2758 个通过、2 个跳过、0 个失败（改动前 2712 个）；工作日志检查通过。

## 下一步

- 用用户手上出现循环的歌重新识别，确认后半段不再重复；旧草稿需要重新识别。
- 长间奏里的字幕、制作人员幻觉行（“ご視聴ありがとうございました”、“作詞・作曲・編曲 …”）可以考虑在融合时按“Qwen 没有对应行 + 典型幻觉文本”自动标记。
- #413（识别质量语料库与回归门槛）仍未开始，循环阈值需要用它校准。

## 已知风险

- Whisper 不再收到歌名、歌手提示，专有名词的写法可能更依赖 Qwen 和校对。
- 仲裁以 Qwen 为准：Qwen 自己漏掉的重复（尤其是口号）只标记不删除，但被替换的 Whisper 循环里如果有真实重复，需要在复核时找回。
- 断点续跑指纹变化，已有的分段识别结果会重新识别一次。

最后更新：2026-11-23 12:00（Asia/Taipei）
