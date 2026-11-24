# Handoff

## 目标

第五十四轮：拆分工程详情页，并给所有页面加行数检查（D-074）。

- `project_detail_screen.dart` 从 1600 行减到 646 行，界面组件移到 `widgets/project_detail_{content,hero,cards,action_panel}.dart`。
- 复核数量按读到的那份工程缓存，不再每次刷新界面都重算。
- `test/architecture/screen_size_budget_test.dart`：`screens/` 下的文件都要少于 1200 行；`local_collections_screen.dart`（1249 行）先登记，只能变短。

第五十二、五十三轮（D-072、D-073）也在这个分支上，PR #520 尚未合并，现在包含三轮。

## Git 现场

- 分支：`arena/3ba64e05-lyric-forge-ktv`，基于 main `5787129`（PR #519 合并后）。

## 已改文件

见工作日志 `2027-01-07-1000`（D-074）、`2027-01-06-1000`（D-073）、`2027-01-05-1000`（D-072）。

## 检查结果

- 沙箱里没有 Dart SDK，用临时 CI 探针在分支上跑格式、分析和测试。
- 提交 `3ebd5465`：`dart format`、`flutter analyze` 通过；`flutter test` 全部通过，共 5460 个（上一轮 5452，+4 卡片文案、+1 复核计数缓存、+3 页面行数预算）。
- 正式 CI（flutter、format-analyze-test-worklog）同样通过。

## 下一步

- 拆分 `local_collections_screen.dart`（1249 行），拆完把它从行数检查的名单里删掉。
- 后续候选：空状态和出错提示统一打磨、批量标记副歌、KTV 彻底删除时检查锁定状态并补撤销测试。

## 已知风险

- 结构调整为主，靠原有工程详情页测试（导入分轨、生成伴奏、演唱语言、删除、复核数量）兜底。
- 复核数量的缓存按对象是否相同判断；仓库每次读取都返回新对象，工程有改动时一定会重算。

最后更新：2027-01-07 10:00（Asia/Taipei）
