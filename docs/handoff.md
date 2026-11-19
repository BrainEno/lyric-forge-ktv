# Handoff

## 目标

审计路线的下一轮（PR #475 已合并为 `0b4c337`）。这一轮多做几个任务：

1. I-01/I-02 导入流程：环境检查页改名“准备识别环境”，两页都显示“1 准备识别环境 — 2 选择歌曲”步骤条；导入页三个卖点胶囊改成一行说明。
2. R-01/R-02 校对收件箱：每行显示歌曲封面；有待复核工程时，已复核的工程折叠在“已复核的工程 · N 个”下面。
3. SE-05/SE-01 设置页：分成“AI 识别”和“故障排查”两组；开发者自检卡改为“试识别一首歌”并移到诊断下面，文案去掉术语；导航提示不再承诺播放和存储设置。
4. 剩余空状态统一：`AppEmptyState` 新增 inline 密度；首页空/失败卡片、歌词列表的两个筛选空状态、后台队列空状态都改用共享组件；筛选藏起所有行时提供“显示全部歌词”。
5. C-01 首页“打开音乐”入口收敛：没在播放时只保留主视觉卡片的按钮；正在播放时页头才显示“打开音乐”；最近播放区块不再带重复按钮。

## Git 现场

- 分支：`arena/8d29a47a-lyric-forge-ktv`，基于 main `0b4c337`。
- 提交：`Name the import steps`；`Fold reviewed projects in the review inbox`；`Move the trial run under troubleshooting`；`Share the remaining empty states`；`Offer open music once on the dashboard`。

## 已改文件

见工作日志 `2026-11-19-1205-name-the-import-steps.md`（步骤条组件、环境检查页、导入页）和 `2026-11-19-1210-fold-reviewed-projects-in-the-review-inbox.md`（校对收件箱）和 `2026-11-19-1215-move-the-trial-run-under-troubleshooting.md`（设置页分组、试识别卡片）和 `2026-11-19-1220-share-the-remaining-empty-states.md`（共享空状态）和 `2026-11-19-1225-offer-open-music-once-on-the-dashboard.md`（首页入口）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。注意：CI 在 `flutter pub get` 之后才运行 `dart format`，排查格式问题以 pub get 之后的结果为准。临时格式探针工作流（`zz-format-probe.yml`）已删除；它在 pub get 之后跑过本轮所有改动文件的格式、analyze 和测试（50 个测试全部通过），最后一处格式差异（首页 `_SectionHeader` 的 children 列表）已按它的结果修正。

## 下一步

- 下一轮候选：P-02 工程详情“音频源管理”折叠（注意 `project_detail_capability_test.dart` 里约 15 个测试直接点人声/伴奏按钮）、L-02 传输入口收敛、A-04 语义标注、N-01 `/quick-play` 入口、Forge Red 品牌色（B-01）。

## 已知风险

- 没有在运行中的应用里看过。详见工作日志。
- 首页正在播放时才显示页头“打开音乐”；如果用户习惯从页头进入，空闲时需要改用主视觉卡片的按钮。
- 歌词列表的空状态改用 page 密度（56 px 图标），在很矮的编辑器窗格里不会滚动，和旧实现一样。

最后更新：2026-11-19 12:35（Asia/Taipei）
