# Handoff

## 目标

拆除 player → transcription 的 feature 依赖，将 KTV 混音的 FFmpeg 设置读取连接留在 app 装配层，保持既有导出行为。

## Git 现场

活动分支 `arena/c6a1709e-lyric-forge-ktv`，基线 `fcd072bfbd636cd98004328c06b9ca8d2b41d14a`。使用 `git status --short`、`git diff --stat` 和 `git log --oneline -5` 核对最终状态；临时验证 workflow 交付前删除，正式 CI 未改。

## 已改文件

KTV 录音服务、应用装配与 app services，feature 依赖图基线及测试，KTV 导出和真实/替身设置装配测试、工作日志和本交接。

## 检查结果

本地无 Flutter/Dart。固定 Flutter 3.47.7 的 Actions run 43014094131：锁定依赖、格式、架构和 KTV 定向测试、`flutter analyze --no-pub --no-fatal-infos lib test tool` 通过；日志检查另行执行，最终 PR Quality Gate 以检查结果为准。FFmpeg 进程和音频设备使用替身，并非实际声音/硬件测试。

## 下一步

继续按 #327 的可收缩基线拆解其余跨 feature 环和 presentation 引用；已移除的 player → transcription 边不可恢复。检查 #415 的 runtime 协议与设备安全实现能力，不能仅在客户端添加假认证。

## 已知风险

现存 lyrics、player、project、transcription 仍有其他循环，静态依赖图不覆盖间接依赖或运行时行为。此次测试使用真实临时文件、真实设置存储与虚拟进程，但没有验证实际 FFmpeg 输出、Windows/macOS 设备和 KTV 音质。#416 屏幕阅读器和 #413 实歌基线仍待人工验证。

最后更新：2026-11-07（Asia/Taipei）
