# Handoff

## 目标

继续解决跨分片的双引擎重复歌词。本阶段为双引擎候选保存每个次引擎片段的原文、源序号和时间，分片结果换算成整段音频时间并标记分片来源；只增加证据，不自动检测、替换或删除歌词。

## Git 现场

活动分支 `arena/d30617d4-lyric-forge-ktv`，开放 PR #412。阶段起点 `df947c51d4d2970b368b90f65da1578bbc58b058`，原始 main 基线 `5bea6660ca5ec95e2a0c4f9d702fcdba6a7f79bf`。记录前 `git status --short`：`M test/resumable_chunked_transcription_service_test.dart`；`git diff --stat`：1 file changed, 7 insertions(+), 4 deletions(-)（格式调整）。`git log --oneline -5`：`da859f2 Track secondary evidence chunk origin`、`81a14bb Record secondary ASR segment evidence`、`df947c5 Record ASR chunk review validation`、`be97a21 Document shared ASR chunk review`、`828a63a Preserve shared ASR review across chunks`。以当前 Git 状态为准；临时验证 workflow 不应进入 PR。

## 已改文件

双引擎融合与分片服务、对应定向测试，以及交接和工作日志导航；前一阶段的分片复核保护也仍在 PR #412。

## 检查结果

本地无 Flutter/Dart。固定 SDK Actions 42952041778：格式、双引擎融合/分片/校对面板测试以及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。工作日志及最终 PR 门禁见后续 Actions。没有真实歌曲、真实模型或设备验证。

## 下一步

在相邻分片的独立检查点合并前研究跨分片候选对应：先验证相同备选引擎、文本和共享音频内有效时间交集及主稿行是否不同，再以保守、可审查方案阻止复制；使用人工基准和真实副歌重复负例验证，不得静默改写人工歌词。

## 已知风险

`secondarySegments` 仅是次引擎候选片段证据，时间戳未验证且不保证对齐准确；`sourceIndex` 仅在该次引擎调用内有效，`secondarySegmentChunkIndex` 仅在当前分片会话内有效，不是模型身份或音频哈希。合并后每行仍只保留一个候选，其他分片证据可能只存在对应检查点；旧工程或已完成旧检查点可能缺字段，不会自动补齐。相邻分片共享关系尚未检测，跨分片自动重复替换仍可能发生；安装资源协调也仍未生产接线。真实歌曲人工基准缺失，不能声称 CER/召回改善或全部重复消除。

手工验证建议：真实长歌曲在重叠分片边界生成候选，检查检查点与合并结果的片段文本、源分片序号和整曲时间，再中断恢复对比；同时核对重复副歌不被自动删除。当前未在设备执行。

最后更新：2026-11-07（Asia/Taipei）
