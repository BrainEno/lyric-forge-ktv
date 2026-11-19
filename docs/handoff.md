# Handoff

## 目标

审计路线的第十四轮（第十三轮 PR #485 已合并为 `c4c73dd`）。用户这一轮只说“接着开发下一轮”，所以按第十三轮交接的建议做：T-02 剩下的 v2 命名单独做一轮，再把状态一节里几项“部分 / 待核”收尾。lib+test 代码量按以往要求不少于 800 行。

1. T-02（D-035）：智能校对去掉版本号。四个 lib 文件和九个测试文件 `git mv` 改名（`run_proofread_use_case.dart`、`proofread_review_assembler.dart`、`proofread_document_composer.dart`、`lyric_proofread_dialog.dart` 等），约三十个标识符去掉 `V2`（`LyricProofreadReviewItem`、`ProofreadRunOptions`、`RunProofreadUseCase` …）；编辑器入口按菜单项命名为 `smartProofread` / `onSmartProofread` / `_openSmartProofread`。持久化的 `'whisper-lyrics-v2'` 等没动。新测试 `proofread_naming_test.dart` 防止回退。
2. E-04：编辑器内容组件的复核队列和播放器参数收成 `LyricReviewControls` 和 `LyricPlaybackControls`（`lyric_editor_review_controls.dart`），筛选后的行、仍有效的选中行、“开始复核”打开哪一行、能否标记复核、播放头所在行和暂停时的拆分点都由它们计算，有单元测试；构造函数从 26 个参数降到 15 个。页面用 `_reviewControls` 组装，仍在 1200 行预算内（1198 行）。
3. E-06：主题 `labelSmall` 从 10 改为 11，小号徽章不再把字缩到 10；`text_theme_floor_test.dart` 要求主题字号都不小于 11。
4. S-05：核对后 `lib` 里只剩两处 `CircleAvatar(radius: 24)`，改用新 token `AppSpacing.avatarRadius`；`source_hygiene_test.dart` 也拒绝 `radius: 数字`。
5. 审计总表状态一节改为“第 14 轮核对”，更新了 T-02、E-02、E-04、E-06、S-04、S-05。

## Git 现场

- 分支：`arena/16f148e6-lyric-forge-ktv`，基于 main `c4c73dd`。
- 提交：`Drop the version suffix from smart proofreading`、`Group the editor's review and playback inputs`。

## 已改文件

见工作日志 `2026-12-01-0930`、`2026-12-01-1100` 两条记录；新决定 D-035；审计总表状态一节。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑，并用了临时探针工作流（合并前删除）。改名后变长或变短的行按 `dart format` 的规则手工重排过；工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- 状态一节里还剩：C-03（识别设置约 590 行，可再拆）、A-04（语义标注未全量走查）。
- `LyricEditorToolbar`、`LyricListPane`、`InspectorPane` 仍各自接收播放和复核的零散参数，可以改为直接接收这两个分组。
- 在真机上确认：11 号小字和小号徽章的观感；编辑器的筛选、开始复核、跟随播放和拆分行为没有变化。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- `labelSmall` 用在约 75 处，字号加 1 后，很窄的行可能换行或截断；没有截图测试能发现这一点。
- 改名只覆盖 `lib` 和 `test`；外部分支或未合并的工作如果还引用旧名，合并时会冲突。
- 状态一节是按代码和注释核对的，不等于运行验证。

最后更新：2026-12-01 11:30（Asia/Taipei）
