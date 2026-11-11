# Handoff

## 目标

继续 #319 独立重识别的安全接入。本阶段实现并测试调用者独立的安装资源协调包装器，但不在生产环境接线。

## Git 现场

基线 `6722216f5649e1a85000c935448f4a0dc36b1d17`，分支 `arena/6d6af082-lyric-forge-ktv`。记录时 `git status --short`、`git diff --stat` 均为空；近期 `git log --oneline -5` 为 `199a65f Fix installation ownership test setup`、`11be2c0 Format installation ownership tests`、`b0ebfc7 Coordinate ASR installation ownership`、`6722216 Merge pull request #409`。以当前 Git 状态为准，临时验证 workflow 不应进入 PR。

## 已改文件

新增 `coordinated_asr_install_manager.dart` 与其定向测试，以及交接、日志和导航。

## 检查结果

本地无 Flutter/Dart。固定 SDK Actions 42848531494：格式、协调包装器及预检取消、协调器、普通识别取消、独立重跑、自检定向测试、`flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。首次测试桩级联赋值编译失败，修正后通过；日志及正式 PR 门禁另见后续 Actions。未验证真实模型或设备。

## 下一步

统一梳理设置、向导和自检安装入口，确保每个 UI State/自检使用独立包装器、所有安装都使用同一 app-scoped coordinator 且无绕过；处理界面管理器外预检、busy 时不触发独立 repair、自检取消时间边界后添加端到端竞态与 widget 测试，再生产接线。

## 已知风险

新包装器目前没有生产调用者；已有自检可能取消其他入口的安装，生产安装尚未受共享资源锁保护。包装器的取消所有权依赖所有同 delegate 的安装调用均使用不同实例和同一 coordinator；绕过会破坏保证。它等待 delegate 安装和 pending cancel 完成，但不能强制 delegate 响应取消；进度流和 delegate 的运行状态仍是共享的。repair、迁移、导入、删除、跨 isolate/进程及闲置 Qwen 显存均未协调；独立重跑尚无生产调用者，也无真实歌曲人工基准。

最后更新：2026-11-07（Asia/Taipei）
