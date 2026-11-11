# Handoff

## 目标

解决同一次引擎长段被多条主稿短句重复采用的问题。PR #411 已保护自动融合；本阶段保护长音频分片合并时跨行复核候选的完整元数据，防止提示和单行采用限制在重叠分片去重时丢失。

## Git 现场

基线 `5bea6660ca5ec95e2a0c4f9d702fcdba6a7f79bf`，分支 `arena/d30617d4-lyric-forge-ktv`。记录时 `git status --short` 为分片服务和测试两个修改文件，`git diff --stat` 为 2 files changed, 121 insertions(+), 64 deletions(-)（相对首个提交的注释及格式调整）。`git log --oneline -5`：`828a63a Preserve shared ASR review across chunks`、`5bea666 Merge pull request #411`。以当前 Git 状态为准；临时验证 workflow 不应进入 PR。

## 已改文件

`resumable_chunked_transcription_service.dart`、`resumable_chunked_transcription_service_test.dart`，及交接与工作日志导航。

## 检查结果

本地无 Flutter/Dart。固定 SDK Actions 42949968911：格式、分片/双引擎融合/校对面板定向测试和 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过；工作日志及正式 PR 门禁见后续 Actions。未在真实模型、歌曲或设备上验证。

## 下一步

用已人工校对的长歌曲、两种引擎顺序和可恢复分片检查重叠区域结果与候选，依 `docs/asr_quality_baseline.md` 比较 CER、召回和重复率。

## 已知风险

分片候选冲突时优先保留完整的跨行候选，可能不显示另一个分片的备选；不会修改已保存人工歌词。若多对一关系横跨两个各自独立处理的分片，单分片融合未必能识别，旧工程缺少标记也无法追溯。文本及时间匹配属启发式，仍可能误判；没有真实歌曲人工基准，不能声称准确率提升或杜绝所有重复。安装资源协调仍未生产接线，独立重跑无生产调用者。

手工验证：构造或使用长歌曲让重复主稿行落在两个相邻分片的重叠区，只在后分片产生跨行候选；确认合并和断点恢复后仍显示跨行提示、没有单行一键采用、可手动编辑；交换两个分片中的提示顺序再试，检查普通候选仍可主动采用。未在设备上执行。

最后更新：2026-11-07（Asia/Taipei）
