# Handoff

## 目标

按“一次生成可用于播放的歌词”方案完成首个独立工作包：记录双引擎融合后的文字/时间快照与需重新对齐的融合风险，不改变模型、歌词或时间选择。

## Git 现场

活动分支 `arena/e0a7c405-lyric-forge-ktv`，基线 `452eedb562287749a4592c71a421bbded9a834e0`。阶段提交 `2166194 Record fusion timing text provenance`、`aaa11ba Document and validate fusion timing snapshots`；使用当前 `git status --short`、`git diff --stat`、`git log --oneline -5` 确认最终现场。临时验证 workflow 必须删除，不更改正式 CI；不得自动合并 PR 或关闭 Issue。

## 已改文件

`FusionTimingEvidence` 契约、双引擎融合和可恢复分片服务、定向测试；`docs/asr_quality_baseline.md`、工作日志、导航和本交接。

## 检查结果

本地无 Flutter/Dart。固定 SDK Actions 42976781024：依赖、格式、融合/分片/证据/歌词检查器/架构契约定向测试及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。日志检查另行执行；没有实歌、实际模型、设备和性能验证。

## 下一步

先依据 #413 建立合法、经人工核对的真实歌曲基线与负例门禁，再独立设计可取消的局部重对齐；需要音频、最终文本、真实 aligner 输入/模型及预处理身份，结果只能作为可复核建议并保护人工修改。

## 已知风险

`timedTextHash` 仅记录与时间一起返回的文本，不证明该文本是对齐器输入；`alignedTextHash` 为 null。`needsRealignment: false` 只表示融合未触发指定风险，不表示已对齐或可播放。使用快照前必须验证索引、文本和时间；不验证音频、模型、录音版本或用户编辑历史。旧/单引擎/降级或获胜旧分片没有此证据；索引变化后可能失效。哈希仍属敏感数据。没有接 UI、自动重对齐或质量放行；真实歌词错误率和时间准确度未知。

最后更新：2026-11-07（Asia/Taipei）
