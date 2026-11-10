# Handoff

## 目标

继续实现选用不同模型独立重识别、保存新旧歌词并审核。本阶段串联所选引擎运行时检查、独立重跑与候选持久化，不更改当前歌词。

## Git 现场

基线 `0931afbc1b853af57c7d63bd02928c5e9431eee4`，分支 `arena/fd8aa424-lyric-forge-ktv`。写入交接前：

```
 M test/features/transcription/independent_project_rerun_workflow_test.dart
 .../independent_project_rerun_workflow_test.dart | 56 +++++++++++++++-------
eb8c1c4 Cover explicit engine and repaired configuration
55b0439 Orchestrate independent model reruns
0931afb Merge pull request #400 from BrainEno/arena/f690cad4-lyric-forge-ktv
```

后续文档与格式化会变化；以实际 Git 状态为准。临时验证 workflow 不应保留在最终 PR。

## 已改文件

新增独立重跑编排和定向测试；更新产品跟进、日志导航和交接。

## 检查结果

固定 SDK Actions run 42658407465：依赖解析后格式化、重跑编排/重跑服务/候选存储定向测试，以及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。本地无 Flutter/Dart；正式 PR 门禁另行运行。测试使用假引擎，未运行真实模型。

## 下一步

实现覆盖现有普通转写、Qwen 对齐、运行时安装和新候选重跑的应用级资源协调，再接入产品界面；并处理长歌分片、进度、候选删除、显式审阅及安全应用/回退。

## 已知风险

新编排默认可创建真实 Qwen/Whisper 适配器，但尚无生产调用者；它只防止自身并发，运行时安装状态检查不是锁。未经全局资源租约不能安全接入 UI，否则可能与现有任务争抢硬件；Qwen 服务还会空闲驻留。保存开始后取消返回 false，不保证可中止提交；现有仓库写失败可能已改变内存。模型内容、跨进程 CAS、TOCTOU、分片完整性及真实歌曲准确率均未验证。

最后更新：2026-11-07（Asia/Taipei）
