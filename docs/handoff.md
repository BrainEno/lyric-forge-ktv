# Handoff

## 目标

继续支持选择不同模型重识别、比较完整歌词版本和智能校对。本阶段实现成对候选的持久化基础，不改变项目当前歌词。

## Git 现场

基线 `0374b32dc614bafee72e045b6fd00fcb7d60aeb8`，分支 `arena/98f90783-lyric-forge-ktv`。记录前：

```
 M test/features/transcription/project_rerun_candidate_store_test.dart
 test/features/transcription/project_rerun_candidate_store_test.dart | 35 ++++++++++++++++++----
ad5d6e9 Test candidate storage failure boundaries
9d1c9d5 Persist independent rerun candidates safely
0374b32 Merge pull request #398 from BrainEno/arena/36e715f5-lyric-forge-ktv
```

文档和格式化会继续变化；以实际 Git 状态为准。临时验证 workflow 不应保留在最终 PR。

## 已改文件

新增独立重跑候选存储服务及文件仓库/冲突测试，更新产品跟进、日志导航与交接。

## 检查结果

固定 SDK Actions run 42651644755：依赖解析后格式化、候选存储/独立重跑/文件项目仓库定向测试，以及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。本地没有 Flutter/Dart；正式 PR 门禁另行运行。测试没有执行真实识别。

## 下一步

接入真实独占引擎与运行时检查、候选管理和审阅界面，包括明确删除与容量提示、持久候选的陈旧性检查及应用时保护人工编辑和事务回退。

## 已知风险

候选存储尚无生产调用者或 UI；最多五对、每对 512 KiB，不自动删除且暂时没有删除接口。保存会增加工程 revision，打开的编辑器可能需要刷新；元数据包含音轨/模型路径和歌词快照，项目 JSON 体积会增长。保存前音轨 hash 和 revision/CAS 不是锁或应用授权；需在后续使用前重新核验，包括模型内容。现有文件仓库的 CAS 仅单实例/单 isolate，跨进程不安全；文件持久化失败时仓库内存状态可能已经更新，不能断言失败后绝无内存副作用。模型准确率、长歌和设备均未验证。

最后更新：2026-11-07（Asia/Taipei）
