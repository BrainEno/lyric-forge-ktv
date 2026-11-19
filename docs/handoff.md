# Handoff

## 目标

审计路线的第六轮（PR #477 已合并为 `aa71744`）。每轮多做几个任务，lib+test 代码量至少 800 行：

1. N-01 播放入口拆分意图：`PlaybackDestination` 统一规则；首页“打开音乐/选择音乐”去音乐库，最近播放恢复到本地播放器，正在播放卡片按歌曲类型打开对应播放器；`/quick-play` 深链用同一规则。
2. L-02 传输入口：`TransferEntry` 统一名称“跨设备传输”、图标和路由；首页头部去掉桌面端“远程音乐库”按钮，改为“更多”菜单第一项（手机也有）；两个传输页标题统一。
3. D-06 首页拆分：`dashboard_screen.dart` 从约 1600 行降到约 520 行，播放区、后台任务卡、列表区和公共外观拆到 `home/presentation/widgets/` 四个文件，行为不变，新增列表区组件测试。
4. C-04 封面收敛：工程播放器、工程详情、歌曲信息对话框、手机下载列表四处裸 `Image.file` 改用 `AppArtwork`（无法解码时显示统一占位）；远程封面本地分支补 `errorBuilder`；新增架构测试防回退。
5. E-04 歌词编辑器参数分组：`LyricEditorContent` 50 个参数中 31 个归入 `LyricUndoRedoControls`、`LyricProofreadActions`、`LyricLineEditActions`、`LyricAuditionControls` 四个不可变对象，剩 23 个；页面用三个构建方法组装，可用性规则不变。

## Git 现场

- 分支：`arena/5b49c7af-lyric-forge-ktv`，基于 main `aa71744`。
- 提交：`Give each player entry its own route`；`Give device transfer one name and two entries`；`Split the dashboard into section widgets`；`Route the last bare covers through AppArtwork`；`Group the lyric editor inputs`。

## 已改文件

见工作日志 `2026-11-25-1000-give-each-player-entry-its-own-route.md`（播放入口拆分）、`2026-11-25-1020-give-device-transfer-one-name-and-two-entries.md`（传输入口）、`2026-11-25-1040-split-the-dashboard-into-section-widgets.md`（首页拆分）、`2026-11-25-1100-route-the-last-bare-covers-through-appartwork.md`（封面收敛）、`2026-11-25-1120-group-the-lyric-editor-inputs.md`（编辑器参数分组）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行；本轮 CI（Flutter Quality Gate）全绿。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。注意：CI 在 `flutter pub get` 之后才运行 `dart format`，排查格式问题以 pub get 之后的结果为准。

## 下一步

- 剩余审计项：P-03（工程详情宽屏，需运行验证）、B-01 品牌红色、S-01 字体、T-02 传输子域简化；编辑器子面板继续改用分组参数（E-04 后续）。

## 已知风险

- 没有在运行中的应用里看过。详见工作日志。
- 首页拆分和编辑器参数分组是脚本改写，依赖 CI 的 analyze 与现有页面测试兜底。

最后更新：2026-11-25 11:20（Asia/Taipei）
