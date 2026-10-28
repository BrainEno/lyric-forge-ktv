# [2026-10-19 23:24] 修复播放进度条拖动并统一时间显示

- Scope: 工程播放器与全屏 KTV 的进度条此前在拖动时每个像素 tick 都触发 seek 且被播放位置流拉回，无法拖动；全屏 KTV 还没有任何时间文本。抽出共享的可拖动进度条控件，拖动期间滑块跟随手指、松手只 seek 一次，并统一显示 `已播/总时长`。
- Files: `lib/features/player/presentation/widgets/seekable_progress_bar.dart` (new), `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/player/presentation/screens/immersive_ktv_screen.dart`, `test/features/player/seekable_progress_bar_test.dart` (new)。
- Validation: `flutter analyze` 对三个改动 Dart 文件无 issue（目录级分析仅剩既有 info 风格提示，均不在改动文件）；`flutter test test/features/player/` 86/86 通过（含新增 5 个控件测试：时间标签、未知时长占位、拖动跟随 + 松手单次 seek、无时长禁拖、`enabled: false` 禁拖）。
- Notes: KTV 录制锁定从 `IgnorePointer` 改为控件 `enabled: false` + 保留 0.55 透明度，交互与视觉语义不变。`now_playing_screen.dart` / `quick_play_screen.dart` 原本已正确（`_dragValue` 模式）本轮不动。仓库未用当前 tall-style 格式化器整体格式化过，因此没有对两个旧屏文件全量跑 `dart format`（会引入数百行无关重排），新增文件保持格式化干净；全文件格式化属于独立清理任务。手动验证清单（未运行，需要真机）：390×844、844×390、1024×768、1366×768、1600×900 连续拖动进度条、KTV 录制锁定态禁拖、紧凑/展开布局。
- Commit: `Fix draggable playback progress bar with time labels`
