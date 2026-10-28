# [2026-10-22 12:58] 契约核对与歌词智能校对 V2 架构方案设计（T0）

- Scope: 完成歌词智能校对与时间轴重建方案（V2）的契约核对与架构调研，产出 docs/lyric_proofreading_v2_plan.md。核对当前代码库转写服务、词级时间戳存储位置、Qwen ForcedAligner 运行机制、人声轨回退逻辑、稳定行标识生成、timingProvenance 元数据枚举，以及 whisper 上文开关配置，为 T1 分词器与清洗服务奠定契约基线。
- Files: docs/lyric_proofreading_v2_plan.md, docs/handoff.md, docs/work_log.md, docs/log/entries/2026-10-22-1258-document-lyric-proofreading-v2-contracts.md
- Validation: flutter test test/features/lyrics 报告 215/215 全量通过；flutter analyze --no-pub 校验通过；dart tool/work_log.dart check 语法与完整性校验通过。
- Notes: 确认 Qwen 词级时间保存在 rawJsonPath 外部 JSON 中未进入 LyricLine 实体；Qwen ForcedAligner 目前随 qwen3-asr 服务端通过 --forced-aligner 启动，尚无独立 /v1/align 端点；Whisper 进程调用尚未开启 -mc 0（未关闭上文条件）。按 T0 规范未修改任何 Dart 源码。
- Commit: Document lyric proofreading v2 contracts
