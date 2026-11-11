# Handoff

## 目标

为跨 feature 依赖建立可收缩 SCC 和跨 feature presentation 引用基线，并记录状态管理与依赖装配边界。

## Git 现场

活动分支 `arena/8d81bdb2-lyric-forge-ktv`，基线 `cce30b84645612ad2aa1acd9171b601145b9422f`。以 `git status --short`、`git diff --stat`、`git log --oneline -5` 核对最终状态；临时验证 workflow 交付前删除，不更改正式 CI。

## 已改文件

`test/architecture/` 中的依赖图、基线、算法及文档契约测试；`docs/architecture_player.md`、`docs/decisions.md`、生成的工作日志导航及本交接。

## 检查结果

本地无 Flutter/Dart，固定 Flutter 3.47.7 的 GitHub Actions 执行格式化、架构测试及分析；最终运行编号和结果以工作日志及 PR 检查为准。格式化补丁由临时 CI 回传；生成的日志通过 Dart 工具 write/check。

## 下一步

继续 #327：选择 project/transcription 或 player/transcription 的一条反向依赖，移动所有权并经 app 组合根注入，补装配行为测试；消除边后同步缩减 SCC 基线。现阶段仅建立防回退基线，没有拆环，不应关闭 #327。

## 已知风险

依赖图只覆盖静态 feature 内 Dart import/export 的可解析 URI，不覆盖动态反射、生成文件或绕过 feature 路径的间接依赖；不支持的指令 URI/注解需显式处理。现有环和跨 feature presentation 引用仍在；不得把静态架构测试当作运行时行为验证。#415 本机 runtime 认证/端口争用、#416 实际屏幕阅读器、#413 实歌基线仍待独立工作。

最后更新：2026-11-07（Asia/Taipei）
