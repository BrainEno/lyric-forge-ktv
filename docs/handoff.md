# Handoff

## 目标

修复全屏 KTV 首次挂载与退出时同步更改 app-level chrome notifier 导致的 `setState() or markNeedsBuild() called during build` / widget-tree-locked 错误。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 活动分支：`arena/65be4adb-lyric-forge-ktv`（active）。
- 基线：`8648e8b`；已验证实现提交：`90cfbebf0586b12f89a318354eb3691fd331560a`。
- 工作区由验证 workflow 收尾并清除临时 workflow；PR 尚未创建。

## 已改文件

- `lib/features/player/presentation/screens/immersive_ktv_screen.dart`：进入/退出 chrome 状态改为 post-frame 通知，进入回调检查 `mounted`。
- `test/features/player/presentation/screens/immersive_ktv_recording_test.dart`：模拟祖先 `ValueListenableBuilder`，验证挂载与卸载均无异常且 chrome 状态最终正确。
- `docs/work_log_index.md`、本文件及本次 bug-fix work-log entry。

## 检查结果

- `dart format`、定向 `immersive_ktv_recording_test.dart` 与完整 `bash scripts/quality_gate.sh --skip-pub-get` 均通过（CI run `41651784524`）。
- work-log `write/check` 通过。
- 真实 Windows 手测未运行；用户提供的 stack 已由 widget regression 在 Flutter CI 中复现其 ancestor-listener 生命周期条件。

## 下一步

1. 创建 PR；待最终 head 的 Flutter Quality Gate 通过后再合并。用户可在 Windows 再试单句编辑，确认不再出现该异常。

## 已知风险

- 本地无 Flutter/Dart SDK，所有格式、测试及分析结果依赖固定工具链 CI。
- chrome 状态在屏幕挂载/卸载所在帧结束时更新；测试验证最终状态，但未做真机视觉闪烁评估。
- 未改歌词文本编辑或识别逻辑；没有主张真实歌曲/设备验证。

最后更新：2026-11-03 22:17（Asia/Taipei）
