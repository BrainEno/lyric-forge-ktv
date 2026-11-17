# Handoff

## 目标

修复用户反馈的问题：识别 "Riders on the Storm" 时，大约 1:30 之后同样的两行一直重复，间奏和演唱部分都是这两行，行数暴增（D-024）。

- Qwen3-ASR 请求按 30 秒分段（`chunk_max_sec = 30`），每段预算 368 个 token。旧预算按 1200 秒一段算，四分钟的歌每段 2176 个 token，解码器一旦陷入循环就会写满。
- 只发送用户填写的识别词作为上下文，不再发送歌名、歌手、专辑（Qwen 会把它们写进间奏）。
- runtime 补丁跳过只解码出标点的分段；旧 runtime 遇到这种失败时，按 180 秒分段重试一次。
- 识别循环检查新增“两到四行一组的循环”，能查出 A B A B A B 这种轮流重复的行。

合并前先征求用户确认。

## Git 现场

- 分支：`arena/10228596-lyric-forge-ktv`，基于 main `2fc91df64fdb8e0cf5877cf27ce982703f476b40`。
- 实验和验证用的临时 workflow 以及它们提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **识别（`lib/features/transcription/`）**
  - `domain/models/qwen_decode_budget.dart`：按分段计算预算。
  - `domain/models/qwen_recognition_context.dart`（新）：只用识别词的上下文。
  - `data/services/qwen3_asr_native_transcription_service.dart`：`chunk_max_sec`，按 180 秒重试，以及元数据 `qwenChunkSeconds`、`qwenChunkFallback`、`qwenContextTerms`。
  - `local_project_transcription_workflow.dart`、`independent_project_rerun_service.dart`：不再拼接标题和歌手的上下文。
- **runtime**：`tool/patches/qwen3-asr-skip-unalignable-chunks.patch`（新），`build-asr-runtime.yml` 的两个平台都应用它，manifest 的 `behaviorPatches` 记录它。兼容版本号不变。
- **校对**：`lyric_asr_loop_detector.dart`（`repeatedBlock`）、`lyric_asr_loop_dialog.dart`、`lyric_draft_health_service.dart`（注释）。
- **文档**：`decisions.md`（D-024）、`high_quality_asr.md`（更正分段说明：带时间戳时最长 180 秒，不是 1200 秒）、`asr_runtime_installation.md`、本文件、工作日志条目 `2026-11-21-1200`。

## 检查结果

见工作日志条目 `2026-11-21-1200` 的 Validation 一节，其中包括真实歌曲（JamendoLyrics，CC 授权）的实测数字。

## 下一步

- 补丁合并到 main 后会自动重建并上传滚动发布的 `asr-runtime-v3`。已安装的用户在下一次安装或修复 runtime 时才会用上补丁，在那之前遇到只有标点的分段会自动重试。
- 用更多真实歌曲（中文、日文、长间奏）确认 30 秒分段，必要时调整分段长度。
- 可以考虑在 Qwen 结果解析阶段就标出可疑的循环分段（目前由校对菜单的识别循环检查处理，需要用户确认）。

## 已知风险

- 30 秒分段在切点附近偶尔会把一句拆开；切点选在附近能量最低的位置，行构建会按时间重新组合。
- 不再把歌名作为上下文后，歌名里的生僻专有名词可能识别得更差，需要用户把它们填进识别词。

最后更新：2026-11-21 12:00（Asia/Taipei）
