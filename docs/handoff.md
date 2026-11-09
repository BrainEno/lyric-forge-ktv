# Handoff

## 目标

用户要求优先解决所有开放的歌词识别改进问题，特别是安全换主模型重跑、两版本比较及智能校对、时间轴易用性，以及副歌遗漏和模糊发音。本阶段只改善已有双引擎逐行候选的比较和恢复。

## Git 现场

基线 `76fbbd3bea4d1bcff4c20d07e21db1736f2011f4`，分支 `arena/d364ab96-lyric-forge-ktv`。生成本交接前的现场：

```
 M docs/work_log_index.md
 M lib/features/lyrics/presentation/widgets/lyric_inspector_pane.dart
 M test/features/lyrics/presentation/widgets/lyric_inspector_pane_test.dart
?? docs/reviews/2026-11-07-asr-product-followup.md
 docs/work_log_index.md                             |  2 +-
 .../presentation/widgets/lyric_inspector_pane.dart | 12 ++++---
 .../widgets/lyric_inspector_pane_test.dart         | 42 ++++++++++++++--------
 3 files changed, 37 insertions(+), 19 deletions(-)
cb4b956 Harden candidate labels and compact review
c8e20d7 Compare both ASR candidates in the inspector
76fbbd3 Merge pull request #394 from BrainEno/arena/67b864b7-lyric-forge-ktv
```

暂存区为空；新文件不计入 `git diff --stat`。最终 PR 不保留临时验证 workflow，以当前 Git 状态为准。

## 已改文件

编辑器逐行候选卡和 widget 测试；开放 Issue/产品阶段计划、工作日志导航和交接。候选比较只在原有未复核的分歧证据存在时出现，采用任一文本不改时间。

## 检查结果

固定 SDK Actions run 42630271940 通过依赖解析后格式化、候选卡和字符差异定向测试、全项目静态分析。首次 run 42629987426 定向测试通过，但分析因新增多余空值断言告警失败，已修复。无本地 Flutter/Dart，未做手动设备和真实歌曲验证；最终 PR 质量门禁以 GitHub 为准。

## 下一步

设计并测试不覆盖现有工程和人工编辑的独立模型重跑及双版本证据契约，随后实现比较和审核，详见 `docs/reviews/2026-11-07-asr-product-followup.md`。

## 已知风险

本阶段未实现重跑、完整版本比较或自动修正，未改善 ASR 模型准确率。旧候选可能缺少主模型原文，只能与当前编辑文本比较；候选本身可能不完整或错误。真实歌曲、时间轴界面和设备行为尚需验证，开放 Issues 未完成验收。

最后更新：2026-11-07（Asia/Taipei）
