# Handoff

## 目标

第五十三轮：把歌词编辑器的保存和试听移出页面（D-073）。`lyric_editor_screen.dart` 从 1198 行减到 783 行，界面和行为不变。

- 保存：`controllers/lyric_editor_save_flow.dart`（`LyricEditorSaveFlow`）。
- 试听：`controllers/lyric_editor_audition_flow.dart`（`LyricEditorAuditionFlow`），三处重复的时长和试听窗口计算合并成一处。

第五十二轮（D-072，拆分听歌页）在同一分支上，PR #520 尚未合并，现在包含两轮。

## Git 现场

- 分支：`arena/3ba64e05-lyric-forge-ktv`，基于 main `5787129`（PR #519 合并后）。

## 已改文件

见工作日志 `2027-01-06-1000`（D-073）和 `2027-01-05-1000`（D-072）。

## 检查结果

- 沙箱里没有 Dart SDK，用临时 CI 探针在分支上跑格式、分析和测试（结果待补）。

## 下一步

- 后续候选：空状态和出错提示统一打磨、批量标记副歌、KTV 彻底删除时检查锁定状态并补撤销测试。
- 超过 1200 行的页面还有 `project_detail_screen.dart`（1600 行）和 `local_collections_screen.dart`（1248 行），目前没有测试限制它们的行数，可以按同样方式拆分。

## 已知风险

- 纯结构调整，靠原有编辑器测试（保存、冲突、试听、校对试听）兜底。

最后更新：2027-01-06 10:00（Asia/Taipei）
