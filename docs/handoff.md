# Handoff

## 目标
修复 Flutter 启动时 Navigator 恢复初始路由触发的 `setState() or markNeedsBuild() called during build`，并区分同一终端日志中的底层 MPV 诊断。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 基线：`main` commit `a5e666ae2285495d372d890f39e2c8d2df9956f9`。
- 分支：`fix/route-observer-build-notification-20261026`；PR #192：https://github.com/BrainEno/lyric-forge-ktv/pull/192。
- 变更通过 GitHub 接口写入；当前环境没有本地 Git 工作树，因此无法提供本地 `git status --short` / `git diff --stat` / `git log` 输出。PR diff 是远端状态的依据。

## 已改文件
- `lib/core/navigation/current_route_observer.dart`
- `lib/main.dart`
- `test/core/navigation/current_route_observer_test.dart`
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`
- 本文件与 `docs/log/entries/2026-10-26-1800-route-observer-post-frame-sync.md`

## 本轮实现
- 将当前路由观察器提取为单独类。
- 对同一帧的多次路由变化进行合并，帧结束后仅发布最新路由名。
- 覆盖启动时路由恢复和后续 push/pop，避免在 Navigator 构建阶段同步通知监听器。
- 不通过降低全局 MPV 日志级别隐藏底层播放错误。

## 检查结果
- Flutter Quality Gate #267 通过：变更 Dart 文件格式检查、work-log lint（0 errors / 0 warnings）、`flutter analyze lib test`、`flutter test`（721 项通过）。
- Root widget workflow #6 通过：`flutter analyze lib/main.dart test/widget_test.dart`、根组件测试、指定 mobile-root 测试及完整 `flutter test` 均通过。
- 质量门记录：https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40303806179
- Root widget 记录：https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40303806271

## 下一步
如果播放实际失败，针对产生 `lavf: Failed to create file cache` 的那首具体音频复现并检查来源路径、格式和 MPV/FFmpeg 错误上下文；不要把它与已修复的 Flutter 路由构建断言混为一谈。

## 已知风险
- `property not found _setProperty(osc, 1)` 由 media_kit/MPV 集成输出；应用代码没有设置 `osc`。
- `lavf: Failed to create file cache` 是独立的 MPV/FFmpeg 源/缓存诊断。上游存在相关报告，但仅凭当前日志无法确定是否同因或是否导致播放失败：https://github.com/Pato05/just_audio_media_kit/issues/22。
- 不降低全局错误日志级别，也不在没有复现的情况下调整缓存设置。

最后更新：2026-10-26 18:00（Asia/Taipei）
