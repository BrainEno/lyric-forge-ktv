# Handoff

## 目标

继续支持选择不同模型安全重识别、比较完整歌词版本和智能校对。本阶段只实现单引擎独立重跑的后端基础，返回内存候选，不写入工程或现有歌词。

## Git 现场

基线 `0e0aefe3b19cdfd22713a66e288512474513d925`，分支 `arena/36e715f5-lyric-forge-ktv`。记录前：

```
 M lib/features/transcription/data/services/independent_project_rerun_service.dart
 M test/features/transcription/independent_project_rerun_service_test.dart
9b2e19a Cover isolated rerun cancellation boundaries
a6780bc Build isolated project transcription candidates
0e0aefe Merge pull request #397 from BrainEno/arena/e785770c-lyric-forge-ktv
```

文档和格式化会继续变化；最终以实际 Git 状态为准。临时验证 workflow 不应留在最终 PR。

## 已改文件

独立项目候选重跑服务、共用项目输入选择器、现有转写工作流、定向测试、产品跟进与日志导航。

## 检查结果

固定 SDK Actions run 42648958879：依赖解析后格式化、独立候选/现有项目转写取消/音频校验定向测试，以及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。本地无 Flutter/Dart；正式 PR 门禁另行运行。测试使用假引擎，未执行真实模型或歌曲。

## 下一步

设计持久化版本及审阅/应用事务，接入独立引擎工厂、运行时检查、进度、UI 和长歌分片；应用前重新核验 revision、实际音轨、内容及模型，并保护人工歌词与回退。

## 已知风险

当前服务没有生产调用者，不会改变现有 UI；候选只在内存，退出即消失。工厂必须产生全新独占实例，避免取消/释放别人的任务；本阶段不做全局资源调度。选择的音频在识别前后做摘要，revision 与输入选择在返回前核查，但无锁、不能排除瞬时变化或返回后的变化，绝不是应用授权；模型路径只是配置标识，未校验模型文件。整首直接交给单引擎，长歌/分片完整性未知。临时文件常规退出清理，异常终止或清理失败可能残留。

最后更新：2026-11-07（Asia/Taipei）
