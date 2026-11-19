# Handoff

## 目标

审计路线的第七轮（PR #478 已合并为 `25698e0`）。每轮多做几个任务，lib+test 代码量至少 800 行：

1. E-04 后续：编辑器工具栏和检查面板直接接收分组参数（`LyricAuditionControls`、`LyricProofreadActions`、`LyricLineEditActions`），不再由页面拆开再传。
2. E-02 参考歌词流程命名：`ReferenceLyricPurpose` 三种用途（纠正文字和时间轴 / 只改文字 / 智能校对提供参考歌词），菜单和对话框标题、说明都从用途读取。
3. D-04 后续：最近播放记录保存歌曲封面，首页“最近在听”显示真实封面；旧记录重播后补上。
4. 共享状态：最后几处自建的加载/错误卡片（识别环境检测、磁盘预检、局部重识别、跨设备传输）改用 `AppInlineLoading` 和 `AppErrorState`；传输页失败后可按失败的那一步重试。
5. B-01 品牌标记：从应用图标取色（`AppColors.brand` 熔炉红、`brandPaper`），新增 `AppBrandMark`，替换侧边栏的通用图标，首页标题旁也显示。红色只用于品牌标记。
6. 播放器去重：`PlaybackFactBadges`（格式 + 歌词状态，全中文）和 `SessionTransportBar` 取代“正在播放”和本地播放器各自的私有 `_InfoChip` 与传输控件包装。
7. R-03 校对页批量操作：有待复核行的工程可“全部标为已复核”，先确认，按版本号保存（不覆盖更新的保存），可撤销。

## Git 现场

- 分支：`arena/d79b928b-lyric-forge-ktv`，基于 main `25698e0`。
- 提交：`Pass the editor groups to the child panes`；`Name the reference lyric flows as a pair`；`Show real covers on the recent listening shelf`；`Move the last own loading and error cards to shared states`；`Apply the formatter to the play history tracking test`；`Draw the brand mark from the app icon`；`Share the playback facts and session transport`；`Apply the formatter to the storage preflight card`；`Mark a whole project reviewed from the inbox`。

## 已改文件

见工作日志 `2026-11-25-1130` 至 `2026-11-25-1230` 的七条记录。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本轮用了一个临时格式探针工作流（合并前已删除）：它对改动文件运行 `dart format` 并把差异写进注解，借此修掉了两个老文件里的格式欠账（CI 会格式检查每个被改动的文件）。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- 剩余审计项：P-03（工程详情宽屏，需运行验证）、A-01（强调色是否从绿色换成品牌红，需维护者决定，且要先解决与错误色 `#E22134` 相近的问题）、S-01 字体、T-02/T-03 传输子域、SE-04 拆分 1008 行的 `AiTranscriptionSettingsSection`、工程播放器 `_TransportPane`/`_PlaybackControls` 合并。

## 已知风险

- 没有在运行中的应用里看过。详见工作日志。
- 品牌标记是按图标绘制的简化版，真实观感需要运行确认。
- “全部标为已复核”依赖编辑器的指纹式复核记录；编辑器打开同一工程时再保存会因版本号冲突提示，这是预期行为。

最后更新：2026-11-25 12:40（Asia/Taipei）
