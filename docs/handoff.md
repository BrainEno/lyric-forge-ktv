# Handoff

## 目标
修复 Flutter 路由恢复时的构建期通知断言，并处理音频-only MPV 适配器启动时写入不支持的 OSC 运行时属性所产生的日志；区分仍需实测的文件缓存诊断。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 当前 `main`：`9c85b5b8e57a30d0a8179dda355d3f0304a99ea5`（PR #192 已合并）。
- 当前分支：`fix/media-kit-audio-osc-property-log-20261026`；PR #193：https://github.com/BrainEno/lyric-forge-ktv/pull/193。
- 当前执行环境无本地 Git 工作树；远端 PR diff/Actions 作为状态依据。

## 已改文件
- 已合并主线：`lib/core/navigation/current_route_observer.dart`、`lib/main.dart`、`test/core/navigation/current_route_observer_test.dart`。
- 当前 PR：`packages/just_audio_media_kit/lib/mediakit_player.dart`。
- 工作日志、索引、归档、交接与本条日志。

## 本轮实现
- 路由观察器在一帧内合并变更并在帧结束后通知监听器；已合并 PR #192。
- 音频-only 的 `just_audio_media_kit` 设置 `PlayerConfiguration.osc: true`，避免 media_kit 默认 `osc=false` 分支把 `osc=no` 作为运行时属性写入不支持 OSC 的音频构建。
- 不降低 MPV 全局日志等级，不通过隐藏错误或关闭缓存来制造“干净日志”。

## 检查结果
- 路由修复主线验证：Quality Gate #270、main 合并后 Quality Gate #271 均通过，包含格式、日志预检、分析及 721 项 Flutter 测试。
- 当前 OSC 修正源代码 head `e1c2cfdc)：Quality Gate #272 通过格式、work-log 预检、`flutter analyze lib test` 与 721 项测试。
- Quality Gate #272：https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40306279221
- 文档更新后仍需以 PR #193 最新 head 的 CI 作为最终验证。

## 下一步
在 Windows 重建并启动后确认 `property not found _setProperty(osc, 1)` 不再出现；若 `lavf: Failed to create file cache` 仍出现且首次播放失败，记录具体音频来源/格式与第一次、第二次播放行为，再针对对应输入路径修复。

## 已知风险
- `NativeReferenceHolder: Allocated ...` 是 media_kit 原生引用分配日志，不是本次 Flutter 断言。
- `lavf: Failed to create file cache` 是独立 MPV/FFmpeg 诊断。上游有相关 `just_audio_media_kit` 报告，但当前 Windows 日志未证明同因或是否造成播放失败：https://github.com/Pato05/just_audio_media_kit/issues/22。
- CI 无法验证本机 Windows MPV 实际播放；本轮只处理已经从配置路径确认的 OSC 属性问题。

最后更新：2026-10-26 18:20（Asia/Taipei）
