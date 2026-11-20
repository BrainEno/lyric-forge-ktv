# Handoff

## 目标

审计路线的第二十二轮（第二十一轮 PR #493 已合并为 `22a9ea8`）。用户反馈歌词识别仍不理想：错字和同音字、漏句（副歌重复、轻声段、和声）、前奏间奏尾奏里的假歌词、断行和时间不准，歌曲语言有普通话、英语、法语和日语。用户选定本轮做自动人声分离，平台是 Windows + NVIDIA 显卡（发布目标 RTX 5080）。要求有效代码量不少于 1000 行，PR 过 CI 后直接合并。

1. 分离工具 `lyricforge-separator`（D-043，`native/vocal_separator`）：
   - htdemucs_ft 的人声网络，ONNX Runtime 上运行，DirectML 优先、CPU 兜底；
   - 读 44.1 kHz WAV，写 `vocals.wav` 和 `accompaniment.wav`，逐行输出 `LF_*` 进度和结果；
   - 命令行、WAV 和协议部分用假引擎做单元测试（18 个）。
2. 模型导出和发布：
   - `tool/vocal_separator/export_htdemucs_vocals_onnx.py` 导出并和 PyTorch 比对；
   - 新工作流 `build-vocal-separator.yml`：Linux 和 Windows 都真正分离一首合成歌曲并检查，main 上发布到 `vocal-separator-v1`。ASR 运行时的工作流没改。
3. 应用：
   - `ManagedVocalSeparatorRuntime` 按需下载、校验、安装；
   - `VocalSeparationPlanner` 决定分离、复用还是跳过；
   - `LocalProjectVocalSeparator` 转码、分离、检查人声响度；
   - 识别工作流在识别前分离（可取消），人声轨写入工程，识别改用它，结果记在 `metadata.transcription.vocalSeparation`；任何失败都回退原曲；
   - 识别设置里的开关（默认开），诊断信息，工程音轨区的说明。
4. 导入人声时去掉自动人声轨的标记，导入的人声永远由用户自己管理。
5. 文档：D-043、README 和 PRD 的实现状态、`high_quality_asr.md`、`local_transcription.md`。

## Git 现场

- 分支：`arena/afd7f12f-lyric-forge-ktv`，基于 main `22a9ea8`。
- PR 合并方式：squash。
- PR #494，squash 合并，标题 `Separate the lead vocal before lyric recognition`。临时探针已删除。

## 已改文件

见工作日志 `2026-12-09-0930`、新决定 D-043。

## 检查结果

- 沙箱里能编译的只有分离工具的核心部分：`lfsep_tests` 用 g++ `-Wall -Wextra -O2` 编译没有警告，18 个测试、154 个检查全部通过。歌曲生成和输出检查两个脚本用假分离器跑过，包括中文输出目录。
- 真正的引擎、模型导出和 Windows 包只能在 CI 上构建（沙箱里没有 ONNX Runtime、CMake 和 Eigen）。PR #494 上新工作流全部通过：
  - 模型导出和 PyTorch 比对通过；
  - Linux CPU 版真正分离了一首 20 秒的合成歌曲，输出检查通过；
  - Windows x64 DirectML 包编译通过，单元测试通过，在中文目录下用 CPU 分离并检查通过。
- PR 上暴露并已修好的问题：
  - demucs.onnx 的提交号写错了；
  - `diffq` 没有 Python 3.11 的包，已用桩模块代替（只有量化模型才用到它）；
  - PyTorch 的注意力快速路径无法导出，已关闭；
  - Linux 改从 NuGet 取 ONNX Runtime，和 Windows 一样。
- 沙箱里没有 Dart/Flutter，靠 CI 和临时探针验证：Flutter Quality Gate 通过；全量 4471 个测试通过，其中改动涉及的测试 114 个；格式没有差异；analyze 只有原有的 info。
- 新增八个 Dart 测试文件（`test/features/transcription/vocal_separation/`）：清单、输出解析、发布契约、分离决策、模型和设置、安装、进程分离器、识别工作流集成。

## 下一步

- 在 RTX 5080 上实际跑一首歌：确认 `metadata.transcription.vocalSeparation.provider` 是 `dml`、耗时多少，以及识别质量（用 `tool/asr_quality_report.dart` 对比分离前后的行召回和 CER，目标是行召回 ≥ 0.95、CER ≤ 0.10）。
- 如果 DirectML 在这个模型上有问题，可以加 CUDA 执行器的包作为第二选择（需要支持 sm_120 的 ORT 版本）。
- 自动生成的伴奏（混音减人声）已经保存，可以作为 KTV 伴奏提供给用户。
- 识别质量的其他问题（假歌词、断行、和声）可以在分离后的人声上继续做：例如用人声响度做静音段检测，删掉间奏里的假歌词。
- 真机验证（第 14–21 轮都没做）：浅色主题、黑胶首页、编辑器列表等。

## 已知风险

- 没有在运行中的应用里看过，DirectML 路径在 CI 上没有 GPU 可测，只验证了 CPU 回退。
- 分离组件约 200 MB，比之前估计的 80 MB 大（模型是 float32，加上 ONNX Runtime 和 DirectML）。
- 合并到 main 并发布 `vocal-separator-v1` 之前，安装会失败，识别照常用原曲。
- CPU 上分离一首 4 分钟的歌可能要几分钟；超过 45 分钟会被当作失败。
- 自动人声轨会成为工程的“人声”音源，编辑器试听默认播放它。

最后更新：2026-12-09 09:30（Asia/Taipei）
