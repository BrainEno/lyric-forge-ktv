# Handoff

## 目标

推进 #319 的参考歌词 ForcedAligner：本轮只交付可单独测试的领域规划器，不修改 V2 UI、歌词文档或工程，不关闭 #319。

## Git 现场

活动分支 `arena/009f50f7-lyric-forge-ktv`，基线 `fc8e764caae30b9cb408d0250a2dc46ac462d3b7`。最终现场请运行 `git status --short`、`git diff --stat`、`git log --oneline -5`；临时验证 workflow 不属于交付差异。

## 已改文件

`reference_forced_alignment_planner.dart`、对应单元测试、产品跟进、工作日志索引和本交接。清理参考歌词保留原始参考索引；对齐结果必须在限额内完整匹配文本、时序及音频边界才会产生带 `forcedAlignment(reference)` 的时间候选。

## 检查结果

本地无 Flutter/Dart。固定 Flutter 3.47.7 的 Actions 43158132183 通过格式、`flutter analyze --no-pub --no-fatal-infos lib test tool`、规划器/参考优先/对齐服务/编排及架构专项测试。工作日志通过 Dart 工具生成和检查；正式 PR 质量门禁另行检查。

## 下一步

将规划器安全接入 V2 参考优先流程和复核 UI：按原参考索引关联、维持受保护行、考虑部分选择/原行回退与全局偏移、冲突检测和用户显式确认；为无 ID 新行准确持久化时间来源，处理异步状态和失败说明，增加用例及界面测试。

## 已知风险

目前无生产调用者，用户尚不能通过 V2 触发参考歌词对齐或应用这些候选。严格的全量一致性要求会拒绝部分、遗漏标点、跨行片段或重叠输出；与真实 runtime 的兼容性和性能未验证。匹配不证明音频中确有该文本或时间准确，也不是自动应用授权。未测试真实音频、原生设备及屏幕阅读器。

最后更新：2026-11-07（Asia/Taipei）
