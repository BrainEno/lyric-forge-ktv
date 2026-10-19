# [2026-10-19 23:38] 全播放界面进度条支持悬停、点击与拖动跳转

- Scope: 上一轮只修了工程播放器与全屏 KTV；用户实测主播放界面与主界面底部固定播放条仍无法拖动/点击跳转。本轮把所有播放进度条统一为同一个交互控件：悬停显示光标处 `mm:ss` 气泡、按下立即跳转、拖动实时显示目标时间并在松手时落位。
- Files: `lib/features/player/presentation/widgets/seekable_progress_bar.dart`（重写为自定义交互进度条，新增 `.mini` 变体与 Semantics）、`lib/features/player/presentation/widgets/global_player_bar.dart`、`lib/features/player/presentation/widgets/mobile_global_player_bar.dart`、`lib/features/player/presentation/screens/now_playing_screen.dart`、`lib/features/player/presentation/screens/quick_play_screen.dart`、`lib/features/player/presentation/screens/player_screen.dart`（沿用共享控件）、`lib/features/player/presentation/screens/immersive_ktv_screen.dart`（沿用共享控件）、`test/features/player/seekable_progress_bar_test.dart`（8 个交互测试）、`docs/lyric_review_alignment_plan.md`。
- Validation: `dart format`（仅新控件与测试文件，避免对旧文件全量重排）；`flutter analyze lib/features/player/` 无 error/warning，仅既有 info 风格提示（38 条，均不在新增代码）；`flutter test test/features/player/` 89/89 通过，其中控件测试覆盖时间标签、未知时长占位、点击跳转、拖动实时时间 + 松手二次落位、悬停气泡与移出隐藏、禁用态、mini 变体无标签行。`dart tool/work_log.dart check` 通过。未运行真实桌面/移动应用，交互手感需人工确认。
- Notes: 底部固定条高度增加（桌面 14px、移动 28px 命中区），移动端命中区未达 48dp 通用触控标准，属细进度条的刻意取舍；悬停气泡绘制在控件上方并允许溢出，若进度条紧贴可滚动视口边缘可能被视口裁剪。语义滑块保留了 increase/decrease ±5s。项目播放器与全屏 KTV 自动获得新交互，无需再次改动。
- Commit: `Make playback progress bars seekable with hover time hints`
