# Handoff

## 目标

审计路线的下一轮（PR #475 已合并为 `0b4c337`）。这一轮多做几个任务：

1. I-01/I-02 导入流程：环境检查页改名“准备识别环境”，两页都显示“1 准备识别环境 — 2 选择歌曲”步骤条；导入页三个卖点胶囊改成一行说明。
2. R-01/R-02 校对收件箱：每行显示歌曲封面；有待复核工程时，已复核的工程折叠在“已复核的工程 · N 个”下面。
3. SE-05/SE-01 设置页：分成“AI 识别”和“故障排查”两组；开发者自检卡改为“试识别一首歌”并移到诊断下面，文案去掉术语；导航提示不再承诺播放和存储设置。

## Git 现场

- 分支：`arena/8d29a47a-lyric-forge-ktv`，基于 main `0b4c337`。
- 提交：`Name the import steps`；`Fold reviewed projects in the review inbox`；`Move the trial run under troubleshooting`。

## 已改文件

见工作日志 `2026-11-19-1205-name-the-import-steps.md`（步骤条组件、环境检查页、导入页）和 `2026-11-19-1210-fold-reviewed-projects-in-the-review-inbox.md`（校对收件箱）和 `2026-11-19-1215-move-the-trial-run-under-troubleshooting.md`（设置页分组、试识别卡片）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。注意：CI 在 `flutter pub get` 之后才运行 `dart format`，排查格式问题以 pub get 之后的结果为准。

## 下一步

- 本轮其余任务见 PR 描述。之后：L-02 传输入口收敛、A-04 语义标注、Forge Red 品牌色（B-01）。

## 已知风险

- 没有在运行中的应用里看过。详见工作日志。

最后更新：2026-11-19 12:15（Asia/Taipei）
