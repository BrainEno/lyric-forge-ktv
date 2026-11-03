# Handoff

## 目标

Phase 4.2 的 `AppServices.instance` consumer 迁移已全部完成并合入 `main`：最后 5 个 ASR/settings/queue consumer 均改成必填构造注入，并由 `lib/app/` 装配。设置存储实例、ASR runtime/preflight、模型恢复、配置保存、下载代理和队列 protective-pause/recovery 语义保持不变；没有修改识别算法、歌词处理或 UI 布局。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 活动分支：`arena/2cf82e60-lyric-forge-ktv`。
- PR #311 已合并，merge commit `cc307c6`；合并后 `main` Flutter Quality Gate run `41630265190` 通过。
- 当前 handoff/work-log 状态同步为 follow-up 文档变更；没有新的功能改动或待修代码问题。

## 已改文件

- `lib/app/transcription_assembly.dart`：新增配置 dialog、runtime setup 和 Settings 屏幕依赖装配。
- `lib/features/transcription/presentation/transcription_screen_dependencies.dart`、`lib/features/settings/presentation/settings_screen_dependencies.dart`：新增必填依赖对象。
- `TranscriptionConfigDialog`、`AsrRuntimeSetupDialog`、设置区、E2E smoke 卡片、全局转写队列条移除 singleton 查询；Dashboard、导入、项目详情和 App 壳透传 app 层提供的依赖。
- 队列面板继续通过原 `TranscriptionQueueEnvironmentRecovery` 完成恢复；同一 settings store/runtime 对象复用。
- 更新架构棘轮、settings/队列保护契约与 dashboard widget test，ratchet 从 5/5 降为 0/0。
- 更新架构说明、识别/架构评审记录、work-log 和本 handoff。

## 检查结果

- PR #311 最终 head `b6c61c0`：Flutter Quality Gate run `41629406817` 通过（变更文件 format、analyze、全量质量门禁测试、work-log preflight）。
- 最终 head 的 10 个专项 check 全绿：ASR install experience、managed storage location、protective pause、queue inline repair、readiness、settings contract、smoke contract、storage preflight、ASR client、widget root。
- 合并后 `main` Flutter Quality Gate run `41630265190` 通过。
- 本地 `git diff --check` clean；相对 Dart import 扫描 0 missing paths；feature executable singleton scan 0 calls。
- 本地无 Flutter/Dart SDK，因此没有本地运行 `dart format`、`flutter analyze`、`flutter test` 或 work-log harness；相应检查由 CI 使用固定工具链完成。没有真实歌曲准确率或设备硬件测试声明。

## 下一步

1. 将本 handoff 与合并后 CI 记录作为 docs-only follow-up 合入 `main`；无需重新验证功能代码。
2. Phase 4.2 收尾后，再继续 roadmap 中的下一项架构工作；真实语料 / 硬件依赖的验证仍遵守既定边界，不用合成 fixture 冒充真实歌曲结果，也不要求用户执行真机测试。

## 已知风险

- 真实歌曲准确率未在本轮测量；本次没有 ASR 算法改动，也不宣称歌词质量改善。
- 本轮没有改麦克风、播放器或原生行为；无需设备测试作为合并门槛。
- Flutter/Dart SDK 本地不可用；格式、分析、Flutter tests 与 work-log harness 均以 CI 为验证来源。

最后更新：2026-11-03 19:45（Asia/Taipei）
