# Handoff

## 目标

推进 #323：将 V2 校对的策略、保护行、可选对齐与复核组装从编辑器抽取到无 UI 用例，不改变行为。此轮不关闭该 issue。

## Git 现场

活动分支 `arena/9f2ab423-lyric-forge-ktv`，基线 `09dd38a59c40e57bf12998f3f073b66d8b28d462`。检查最终状态请运行 `git status --short`、`git diff --stat` 和 `git log --oneline -5`；临时验证 workflow 不应出现在交付差异中。

## 已改文件

V2 编排用例、编辑器 screen 的调用、用例单元测试、校对 UX 撤销说明、工作日志与本交接。UI 仍负责引用输入、review、revision 防护、时间轴确认及提交。

## 检查结果

本地无 Flutter/Dart。固定 Flutter 3.47.7 的 Actions 43023659317 通过格式、定向领域/编辑器/架构测试和 `flutter analyze --no-pub --no-fatal-infos lib test tool`；首次验证发现的 token 类型导入缺失已修复。正式 PR 全量质量门禁另行检查。

## 下一步

继续 #323：抽取其他两个编辑流程，缩减 screen 并核对所有验收条件；独立审计其他异步编辑流程及时间轴确认竞态。

## 已知风险

#323 的 screen 行数、其他流程和全部 UX 文档仍未满足验收。#319 的 Whisper 第二意见自动读取及参考优先策略使用 ForcedAligner 尚未实现，本次保留原行为。未在真实设备手测 UI、屏幕阅读器、音频、ASR 或实歌准确率；对齐测试使用注入 runner。执行中的原生对齐不会被取消。

最后更新：2026-11-07（Asia/Taipei）
