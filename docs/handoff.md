# Handoff

## 目标

继续支持安全换模型、比较完整歌词版本和智能校对。本阶段为来源可追溯的非分片双引擎快照记录源音频摘要，提供独立、保守的陈旧性校验。

## Git 现场

基线 `e101d31e7d712eabc8c2e6c484863bb9b740e553`，分支 `arena/e785770c-lyric-forge-ktv`。此交接前：

```
 M docs/reviews/2026-11-07-asr-product-followup.md
 M lib/features/transcription/data/services/asr_evidence_audio_verifier.dart
 M test/high_quality_transcription_service_test.dart
42de005 Guard the shared normalized audio provenance
e9cbb6c Reject source changes while hashing
ab71030 Verify ASR evidence against source audio
e101d31 Merge pull request #396 from BrainEno/arena/737d1be0-lyric-forge-ktv
```

工作日志与格式化完成后还会变动；以实际 Git 状态为准。临时验证 workflow 不应留在最终 PR。

## 已改文件

独立证据 schema、最高质量转写服务、音频校验服务及其定向测试，产品跟进、工作日志导航与交接。

## 检查结果

固定 SDK Actions run 42644514145：依赖解析后格式化、音频证据/双引擎/分片/工作流取消定向测试及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。本地无 Flutter/Dart；真实歌曲、设备及最终 PR 门禁另行验证。

## 下一步

设计不覆盖手工草稿的独立重跑候选及审阅工作流：实际输入选择、工程 revision 和模型内容校验、并发/取消与分片需一并处理，然后再接入比较和 UI。

## 已知风险

校验器调用方必须使用工程实际选定输入（vocal、normalized、original 中首个存在的路径），不可默认 original。两次摘要及文件 stat 不是锁，不能证明中途没有瞬时变化；使用前应再次校验并解决 TOCTOU、工程和模型版本。外部预标准化音频/自定义 preparer、旧快照、分片及降级无可验证摘要。当前没有 UI、重跑、自动纠错或真实识别率数据。

最后更新：2026-11-09（Asia/Taipei）
