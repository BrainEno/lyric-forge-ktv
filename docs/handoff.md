# Handoff

## 目标

审计路线的第二十三轮（第二十二轮 PR #494 已合并为 `2c300a5`）。用户要求“接着做下一轮”，并顺带修一下首页上出现两次、位置不好看的品牌标识。下一轮按第 22 轮报告的建议：在分离后的人声上用人声响度找出没人唱的段落，删掉那里编出来的歌词，改进行的时间。要求有效代码量不少于 1000 行，PR 过 CI 后直接合并。

1. 人声检查（D-044）：
   - `PcmWavEnergyReader` 读 16 位 PCM WAV 的 20 ms 响度（后台 isolate）；
   - `VocalActivityAnalyzer` 按这首歌的相对阈值找出有人唱的段落，人声轨不干净（响亮和安静相差不到 18 dB）时不做判断；
   - `VocalActivityLyricGate` 删掉没人唱的行、把拖进静音的起止时间收到人声上、记下有人声却没有歌词的段落；没人唱的行太多时一行都不删；
   - 识别工作流在从人声轨识别后、写入工程前执行，结果记在 `metadata.transcription.vocalCheck`，文档里存 `metadata.vocalCheck`；任何失败都保持草稿原样。
2. 编辑器识别摘要：新增“有人声没歌词 N 处”，不展开就列出前三处时间，补上歌词后自动消失；展开后说明删了哪些行、收紧了多少行。
3. 品牌标识：侧边栏顶部的标识和导航图标对齐在同一列（展开的侧边栏不再居中漂在图标和文字之间）；有侧边栏时首页标题旁不再重复显示标识，窄屏没有侧边栏时保留。
4. 分离开关的说明改成实际下载大小（约 110 MB，解压后约 200 MB）。
5. 文档：D-044、`high_quality_asr.md`、`local_transcription.md`、工作日志。

## Git 现场

- 分支：`arena/55a1ae77-lyric-forge-ktv`，基于 main `2c300a5`。
- PR 合并方式：squash，标题 `Check recognised lyrics against the separated vocal`。临时探针合并前删除。

## 已改文件

见工作日志 `2026-12-10-0930`、新决定 D-044。

## 检查结果

- 沙箱里没有 Dart/Flutter，格式、analyze 和测试都靠 PR 的 Flutter Quality Gate 和临时探针。
- 新增测试：`test/features/transcription/vocal_check/`（记录、响度分析、草稿检查、WAV 读取、用真实 WAV 文件的端到端检查）、识别摘要的人声检查测试、识别工作流集成用例、侧边栏标识对齐和首页标识去重用例。

## 下一步

- 在 RTX 5080 上实际跑几首歌：看 `metadata.transcription.vocalSeparation.provider` 是否为 `dml`，看 `metadata.transcription.vocalCheck` 删了哪些行、有没有误删，按 `profile` 里的响度概况调整阈值；用 `tool/asr_quality_report.dart` 对比行召回和 CER（目标行召回 ≥ 0.95、CER ≤ 0.10）。
- “有人声没歌词”目前只指出位置：可以加一键对该段重新识别（复用“重新识别这一段”）。
- 被删的行目前只能在摘要里看到前两行原文：可以加一个列表，一键恢复误删的行。
- 自动生成的伴奏已经保存，可以作为 KTV 伴奏提供给用户。
- 真机验证（第 14–22 轮都没做）。

## 已知风险

- 阈值是用合成音频和常见分离结果定的，没有在真实歌曲上评测；轻声、气声很重的段落可能被当成没人唱（有“超过 35% 就不删”的保护，但单行仍可能误删）。
- 用户导入的人声轨如果其实是整首混音，会被判为不可靠而跳过；如果串音不严重但有伴唱，伴唱段也会算作有人唱。
- 侧边栏标识对齐依赖 NavigationRail 展开时给 leading 的宽度，靠新的组件测试保证。
- 没有在运行中的应用里看过。

最后更新：2026-12-10 09:30（Asia/Taipei）
