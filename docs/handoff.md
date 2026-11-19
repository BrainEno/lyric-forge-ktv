# Handoff

## 目标

审计路线的第十轮（第九轮 PR #481 已合并为 `e4aa1f7`）。每轮多做几个任务，lib+test 代码量至少 800 行。用户确认自己的模型目录是 `D:\Models\LyricForge\ASRRuntime`，即 B-02 遗留问题里的 “LyricForge ASRRuntime” 是真实的目录名。

1. 模型目录写成路径：存储层本来就能找到 `D:\Models\LyricForge\ASRRuntime`（盘符根、`Models/LyricForge/ASRRuntime` 候选、自动查找、粘贴路径），问题出在文案。界面原来把它写成 “LyricForge ASRRuntime”（像产品名）和 “已有的 ASRRuntime”（不说在哪）。新增 `AsrFolderText`：按平台分隔符写成路径（Windows `LyricForge\ASRRuntime`，其他平台 `LyricForge/ASRRuntime`），卡片、粘贴弹窗和“没找到”提示里给出完整示例（`D:\Models\LyricForge\ASRRuntime`、`/Volumes/Data/Models/…`、`/mnt/data/Models/…`）；按钮改为“浏览模型文件夹”“粘贴已有模型文件夹的路径”。安装弹窗和设置页原来各存一份文案，现在共用。设置页通过 `asr_existing_model_actions.dart` 的 export 拿到它，没有新增跨功能的 presentation 依赖。
2. 全屏 KTV：原来任何按键都只会唤出控件。现在空格播放/暂停（只在全屏界面本身有焦点时，Tab 到按钮后空格仍按按钮），←/→（含 Shift）快退/快进 5 秒且可按住连发，Ctrl/⌘+←/→ 切歌；处理了的按键会唤出控件，没有歌曲时按键交给上层。点击歌词会把焦点从按钮收回。控件层：标题加粗、下面显示歌手，上下两组控件后面各有黑到透明的渐变遮罩（不拦截点击），退出按钮提示“退出全屏 KTV（Esc）”，桌面端底部显示按键说明。歌词加载失败改用 `AppErrorState`，可以重试。
3. 错误文字对比度（D-032）：错误红 `#E22134` 当文字时在 bgBase 上 4.0:1、bgSurface 上 3.2:1，不到 4.5:1。新增 `AppColors.errorText = #FF8585`（同色相）：bgBase 8.0:1、bgSurface 6.3:1、bgHighlight 4.6:1，在红色错误横幅里也高于 4.5:1。19 个文件 31 处错误文字、旁边的小图标、危险操作的文字按钮和输入框错误提示都改用它；填充、边框、底色、大图标、徽标和 `colorScheme.error` 仍用 `AppColors.error`。
4. 传输子域（T-02 第一部分）：手机端歌曲、艺人/专辑、下载管理三屏各自画红字、裸转圈和“没有匹配…”。新增 `transfer_list_states.dart`：`TransferErrorBanner`（带底色的横幅、可关闭、读屏会播报）、`TransferListLoading`（说明正在读取什么）、`TransferEmptyResult`（按原因给标题：搜索无结果时引用关键词并提供“清除搜索”，歌曲列表的筛选无结果时提供“显示全部”，真的为空时说明怎样添加）。

## Git 现场

- 分支：`arena/7600048b-lyric-forge-ktv`，基于 main `e4aa1f7`，PR #482。
- 提交：`Name the model folder as a path`、`Give fullscreen KTV keys and scrims`、`Lift error text to AA`、`Share transfer list states`、`Remove the format probe and update the handoff`。

## 已改文件

见工作日志 `2026-11-27-0930` 至 `2026-11-27-1300` 的四条记录；决定见 D-032；审计总表 `artifacts/ui-audit/reports/issues.md` 已更新 B-02、K-01（11-19 已完成逐字扫光）和 T-02 的进度。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑。本轮同样用了临时探针工作流（合并前已删除）。靠它修掉了：设置页直接引用新文案文件触发的跨功能依赖基线测试失败（改为经现有文件 export），几处格式问题（包括被改动文件里原有的格式欠账），以及四条多余 import 的 analyze 提示。最后一次探针：3287 个测试全部通过，analyze 回到基线的 186 条提示。行长度在本地按字符数检查过；工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- T-02 剩余：桌面传输中心和 v2 命名；审计总表里没有 T-03 条目。
- 小尾巴：`local_collections_screen.dart` 里 `onReorder` 的弃用提示；`reference_alignment_review`、`review_inbox` 里还有两处强调色用法待复查。
- 在真机上确认全屏 KTV 的按键和遮罩深浅（`ImmersiveKtvScreen.scrimAlpha` 为 0.72），以及新错误红在各页面上的观感。
- 待用户决定：R-03 全局批量复核按钮。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- 全屏 KTV 的方向键现在总是快进/快退，Tab 到按钮后也不再做方向焦点移动；进度条获得焦点时仍由进度条自己处理方向键。
- 设置页的 “测试识别” 卡片 `_Notice` 用传入颜色做底色、文字保持白色，所以仍传 `AppColors.error`，在来源扫描测试里列为例外。

最后更新：2026-11-27 13:30（Asia/Taipei）
