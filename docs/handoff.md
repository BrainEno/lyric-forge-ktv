# Handoff

## 目标

继续 #319 独立重识别。本阶段添加单 isolate 共享 ASR 资源协调器，并在独立重识别工作流中持有资源直到准备、识别、取消清理及保存结束。

## Git 现场

基线 `3f48461901b14e66bce836be7a3df71cc3cda515`，分支 `arena/45d76760-lyric-forge-ktv`。后续提交以 `git status --short`、`git diff --stat` 和 `git log --oneline -5` 为准；临时验证 workflow 不应保留。

## 已改文件

ASR 资源协调器、独立重跑工作流、两组定向测试、交接、工作日志和导航。

## 检查结果

固定 SDK Actions 42781526241：依赖解析、格式化、协调器/重跑工作流/重跑服务/候选存储测试、`flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。本地无 Flutter/Dart。日志检查及正式 PR 门禁另见 GitHub；未运行真实模型或设备。

## 下一步

将同一个 app-scoped 协调器安全接入普通工程识别、ForcedAligner 和运行时安装/修复各入口；覆盖取消、启动前预检和生命周期竞态，解决空闲 Qwen 服务占显存后再接入独立重跑 UI。

## 已知风险

当前只有独立重跑使用协调器，还没有生产调用者，不能阻止普通识别、安装或对齐并行。协调仅适用于同一 isolate 中显式共享同一实例的参与者，不是跨进程文件锁；空闲 Qwen 服务可能仍占显存。失败的引擎停止或清理可能导致资源状态不明；不应将此阶段视为完整的全局协调。无真实歌曲基准或设备验证。

最后更新：2026-11-07（Asia/Taipei）
