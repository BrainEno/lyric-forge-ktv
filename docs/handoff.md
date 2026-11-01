# Handoff

## 目标
两步：先是 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 记录「识别结果比第一版更差」与「编辑器/导航过复杂」的源码级根因与分阶段计划（已合并）；再修复 PR #271 合并后残留的红色质量门禁（本分支）。下一次会话应从下面「下一步」的第 1 条开始执行识别质量修复。

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/7a3233a0-lyric-forge-ktv`，基于 `main@003243a`。
- 该分支包含 1 个修复提交（恢复绿色门禁）；工作区在提交后应为 clean。

## 已改文件
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart` — 补 `dart format`；删除 PR #271 遗留的不可达辅助方法 `_editTimestampDialog`；行「复制」动作改为真正写入剪贴板。
- `docs/log/entries/2026-11-01-1156-recognition-quality-ux-review.md` — 审查报告的工作日志条目（已随 #272 合并）。
- `docs/log/entries/2026-11-01-1221-restore-green-quality-gate.md` — 本次门禁修复的工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成/导航同步。
- `docs/handoff.md` — 本文件。

## 检查结果
- 本地无 Flutter/Dart SDK。本次通过一个临时 CI workflow 在固定版本工具链（Flutter 3.47.7 / Dart 3.11.4）上执行真实验证，随后删除该 workflow 与报告文件：
  - `dart format`（目标文件）=> `Formatted 1 file (0 changed)`，exit 0。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => 唯一致命项为 `unused_local_variable`（复制动作未使用文本），已由真实的剪贴板写入消除；其余均为 info。
  - `flutter test --no-pub` => `+854 ~1: All tests passed!`，exit 0。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：对提交前状态逐字节重建三个生成文件（一致），新增条目后 lint 0 error。
- 相对链接存在性检查与 `git diff --check` 通过；PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知遗留
- `main` 在 PR #271 合并时即为红色（格式检查失败），本分支是把它修绿的那一次；后续任何「CI 变红」的判断都应以此为基线。

## 下一步
1. Phase 0：建立质量基线（人工校对 5–10 首歌 + `tool/asr_quality_report.dart`，输出行召回、CER、重复行率、时间戳边界误差）。
2. Phase 1 三项高收益修复：`high_quality_transcription_service.dart` 融合匹配（子串窗口相似度 + 被主行时间包住则不插入）、`service_locator.dart` 去掉全局 3 分钟分片、`resumable_chunked_transcription_service.dart` 合并时保留 metadata 且检查点指纹纳入配置。
3. Phase 1 其余项：Whisper 解码参数与 `--prompt`、最高质量模式自动降级；随后 Phase 2（Whisper 单模型全平台可安装）。

## 已知风险
- 报告中的量化重复行率来自对融合算法的 Python 复刻与合成语料，**不是**真实歌曲上的实测值；真实数字必须由 Phase 0 的语料给出。
- `test/high_quality_transcription_service_test.dart` 目前把「主行内部的一个词变成独立行」写成期望值，任何融合修复都会让该测试失败，必须同步改为新的契约。
- `docs/high_quality_asr.md`（整首一次送入）与 `docs/local_transcription.md`（3 分钟分片）互相矛盾，修复落地时需要一并订正。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。

最后更新：2026-11-01 12:21（Asia/Taipei）
