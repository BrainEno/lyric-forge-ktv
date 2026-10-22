# Handoff

## 目标

实现歌词校对 V2 的 T4：referenceFirst 生成可审阅的歌词提案，不直接落盘；复用已有参考歌词清洗、token 对齐、行级对齐、时间补全和撤销/应用边界。

## Git 现场

- main 基线：`8eb2847ae6664e33ed274200d03f52ae5629c1eb`（T2b 已合并）。
- 工作分支：`feat/lyric-proofreading-t4-reference-first-20261022`。
- 测试先行提交：`f5b71681b51de04211a1026b1b56b728ddba5d4e`；当前实现提交：`1b883babf15de73368f71995c0bfef09c6a8766d`。
- 当前环境只有 GitHub API，没有本地 checkout 或 Dart/Flutter 工具链；PR 保持 Draft，待本地验证。

## 已改文件

- `lib/features/lyrics/domain/proofreading/reference_first_pipeline.dart`：清洗参考歌词并映射回原始索引；计算 token coverage；复用行级对齐和参考时间应用服务生成提案；区分绿色/琥珀色/锁定行，输出未匹配 ASR 行供恢复。
- `test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart`：覆盖 sanitizer 与原始行索引、参考/ASR 时间来源、漏行插值与未匹配行、保护行、时间轴冲突及空参考拒绝。
- `docs/lyric_proofreading_v2_plan.md`、`docs/work_log_index.md`：记录 T4 实施中，T4 尚未标为完成。
- `docs/handoff.md`：更新当前唯一中断点。

## 检查结果

- 静态审查：该流水线只返回建议文档和行级 verdict，不保存项目、不修改传入的草稿对象；保护行恢复为原始文本和时间。
- 未运行 `dart format`、定向 `flutter test`、`flutter analyze --no-pub`、`flutter test test/features/lyrics` 或 work-log 检查，因为当前没有 Dart/Flutter 工具链。
- 没有创建不可变 work-log 条目，也没有手动编辑生成文件 `docs/work_log.md`。

## 下一步（唯一）

本地运行：

```powershell
dart format lib/features/lyrics/domain/proofreading/reference_first_pipeline.dart test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart
flutter test test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart
flutter analyze --no-pub
flutter test test/features/lyrics
dart tool/work_log.dart write
dart tool/work_log.dart check
```

全部通过后再将 T4 标记完成、写不可变日志，并把 PR 标记为 Ready。

## 已知风险

- Qwen ForcedAligner 的任意参考文本适配仍未实现；没有声学对齐证据时，插值/估算时间需人工复核。
- 若恢复受保护行后与邻行仍存在时间冲突，该冲突会明确标为琥珀色，保护行本身不被重写。
