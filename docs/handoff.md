# Handoff

## 目标

新增三个校对与交付工具：

- 「校对」菜单新增“打轴（边听边标时间）”：播放中按空格逐行记录开始时间，“按住”模式还能记录结束时间，可撤回、回退重打、慢速播放和反应补偿。
- 「校对」菜单新增“语速异常检查”：按全曲语速找出过快、过慢的行，并给出结束时间建议。识别摘要卡新增“语速异常 N 行”提示。
- 导出新增“逐字 LRC”和“ASS 卡拉 OK 字幕”，逐字时间按字数估算。

所有改动都是可撤销的编辑，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/f913bbc3-lyric-forge-ktv`，基于 main `b582d99c8626f2a1696f1ab12b368df5dd3425f7`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域服务（`lib/features/lyrics/domain/services/`）**
  - `lyric_tap_sync_session.dart`（新）：打轴状态，包括按键、松开、撤回、回退和防抖。应用时处理收尾、间奏判断、上一行收尾、后续平移，并写入 `manual` 来源。
  - `lyric_pace_analyzer.dart`（新）：计算全曲语速中位数，判定过快和过慢的行并给出结束时间建议，应用时写入 `autoRepaired`。
  - `lyric_karaoke_timing_service.dart`（新）：拆分逐字单位并按权重分配时间，误差累计，总和精确。
  - `lyric_export_encoder.dart`：新增 `karaokeLrc` 和 `ass` 格式、`assLeadIn` 选项、`assTimestamp`；LRC 头部改为共用。
  - `lyric_draft_health_service.dart`：新增 `paceRows`。
- **界面**
  - `widgets/lyric_tap_sync_dialog.dart`（新）：打轴对话框。通过 `LyricTapSyncTransport` 抽象播放器，外推播放位置；大按钮按下即记录时间。
  - `widgets/lyric_pace_check_dialog.dart`（新）。
  - `controllers/lyric_batch_text_tools_coordinator.dart`：接入两个新工具。打轴前确保本工程音频已加载，并清除试听窗口。
  - `lyric_batch_text_edit.dart`（`tapSync`、`paceCheck`）、`lyric_proofread_menu_button.dart`、`lyric_editor_toolbar.dart`、`lyric_editor_content.dart`、`lyric_recognition_summary_card.dart`、`lyric_export_dialog.dart`（ASS 提前显示开关、逐字估算说明、预览跳过头部）。
- **文档**：`decisions.md`（D-020）、本文件、工作日志条目 `2026-11-17-1800`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。

- `dart format`：改动文件已格式化。
- `flutter analyze`：没有 error 或 warning，186 条 info，与 main 相同。
- `flutter test` 全量：2516 通过，2 跳过，0 失败（main 为 2477 通过）。
- `dart tool/work_log.dart write` 和 `check`：通过（唯一的 warning 是旧条目的问题，早已存在）。
- `lyric_editor_screen.dart`：仍为 1178 行。

## 下一步

- 用 #413 的真实歌曲语料校准阈值：语速 2.2×、6 字/秒、0.4×、2 秒、1.4×；打轴 120 ms 防抖、8 秒间奏、600 ms 外推上限。
- 如果识别引擎将来提供词级时间戳（Qwen3-ASR 的 `words`），可以让逐字 LRC 和 ASS 优先使用真实时间，比例估算作为回退。
- 打轴目前只记录行级时间。逐字打轴（每个字按一次）可以在同一个会话模型上扩展。

## 已知风险

- 逐字时间按比例估算，长音、拖腔处会有偏差；导出对话框已说明。
- 语速检查以全曲中位数为基准，快慢段落差异很大的歌曲（如说唱段落）可能误报。建议都可以取消勾选，也可以撤销。
- 打轴精度依赖播放器上报位置和外推；部分平台上播放器内部缓冲可能带来几十毫秒的固定偏差，可以用反应补偿抵消。

最后更新：2026-11-17 18:00（Asia/Taipei）
