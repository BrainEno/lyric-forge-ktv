# Handoff

## 目标
处理 Windows/Linux 音频-only MPV 后端中的 `lavf: Failed to create file cache.`，同时保留正常内存/网络缓存，并将实机未验证的事项明确记录。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 当前 `main`：`1e2d6a5a062e9701325ab46592698bb425587bf9`（PR #192、#193 均已合并）。
- 当前分支：`fix/mpv-disk-cache-warning-20261026`。
- 当前 PR #194：https://github.com/BrainEno/lyric-forge-ktv/pull/194。
- 当前环境没有本地 Git 工作树；远端文件、PR diff 与 GitHub Actions 是验证依据。

## 已改文件
- `packages/just_audio_media_kit/lib/mediakit_player.dart`：在适配器 ready 阶段、媒体打开之前设置 `cache-on-disk=no`。
- `docs/log/entries/2026-10-26-2000-disable-mpv-disk-cache.md`、`docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` 与本文件。

## 本轮实现
- MPV 手册说明 `cache-on-disk` 会将 packet 数据写入临时文件；明确设为 `no` 后，常规缓存仍可用，包数据留在内存。
- 不使用 `cache=no`，不降低 MPV 全局日志等级，也不重写播放时序。
- 先前路由断言修复 PR #192 与 OSC 属性修复 PR #193 已合并；这条缓存告警是独立诊断。

## 检查结果
- 主线改动前 Quality Gate #275 已通过格式、work-log preflight、analyzer 与测试：https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40311320773。
- MPV 选项语义依据：https://mpv.io/manual/master/。
- PR #194 的最新 CI 需要在本次文档提交后复核。
- 当前环境无法运行 Windows 原生 MPV 播放；没有声称本地播放已验证。

## 下一步
检查 PR #194 最新 head 的所有 CI。通过后由仓库维护者决定是否合并；重建 Windows 应用后实测本地文件与网络输入的首次播放，观察警告是否消失以及首播是否正常。如果首播仍失败，继续根据具体源路径、格式和播放错误分析，不以消除这行日志代替播放验证。

## 已知风险
- 上游曾报告同一条日志，并指出关闭缓存选项可令日志消失却未必解决首播失败：https://github.com/Pato05/just_audio_media_kit/issues/22。
- `NativeReferenceHolder: Allocated ...` 是原生引用分配信息，不是 Flutter 构建断言。
- 当前改动针对可选磁盘缓存创建路径；Windows 实机结果仍未知。

最后更新：2026-10-26 20:00（Asia/Taipei）
