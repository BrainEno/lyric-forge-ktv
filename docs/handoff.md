# Handoff

## 目标

继续支持选择不同模型重识别、比较完整歌词版本和智能校对。本阶段为已保存的重跑候选提供当前歌词、音轨和模型校验状态；不修改歌词。

## Git 现场

基线 `2f3bfb365439c0224bde419c2c274613df537ea8`，分支 `arena/f690cad4-lyric-forge-ktv`。记录前：

```
 M lib/features/transcription/data/services/project_rerun_candidate_assessor.dart
 M test/features/transcription/project_rerun_candidate_assessor_test.dart
 .../project_rerun_candidate_assessor.dart | 3 ++-
 .../project_rerun_candidate_assessor_test.dart | 30 +++++++++++++---------
a04ddf0 Mark model identity as unverified
5496287 Assess saved ASR candidate freshness
2f3bfb3 Merge pull request #399 from BrainEno/arena/98f90783-lyric-forge-ktv
```

文档和格式化会继续变化；以实际 Git 状态为准。临时验证 workflow 不应保留在最终 PR。

## 已改文件

新增候选复核状态服务及定向测试；复用候选存储中的原稿比较逻辑；更新产品跟进、日志导航和交接。

## 检查结果

固定 SDK Actions run 42655844804：依赖解析后格式化、候选复核/候选存储/独立重跑定向测试，以及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。本地没有 Flutter/Dart；正式 PR 门禁另行运行。测试没有执行真实识别。

## 下一步

接入真实独占引擎及运行时和资源协调，设计候选管理与审阅界面；候选应用要显式确认、重新校验、保护人工编辑并支持事务回退。还需安全删除候选及容量提示。

## 已知风险

状态只表示检查时刻，音频、歌词、模型或工程之后仍可能变化；hash/stat 非锁，CAS 不保证跨进程，不能将匹配作为自动应用授权。原稿比较包含完整 metadata，可能保守报变化；模型内容与参数始终未校验，既有保存数据没有模型哈希。候选服务尚无生产调用者/UI，最多五对且无删除接口；现有仓库持久化失败可能已改变内存。长歌、设备及真实歌曲识别率仍未验证。

最后更新：2026-11-07（Asia/Taipei）
