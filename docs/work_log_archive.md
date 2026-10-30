# Work Log Archive

> Navigation only. The full text of every entry lives in `docs/log/entries/<file>.md`;
> the newest entries are listed in [work_log.md](work_log.md). History is preserved verbatim and is never deleted.

## 2025-04 | App skeleton and playback basics

- [2025-04-23 22:45] Phase 1.5: 实现快速播放模式 `feat: add quick play mode with play history` ([entry](log/entries/2025-04-23-2245-add-quick-play-with-history.md))
- [2025-04-22 22:30] Phase 1.3 Task 6: 重构 PlayerScreen 接入真实音频播放 `feat: refactor PlayerScreen with real audio playback and source switching` ([entry](log/entries/2025-04-22-2230-player-screen-real-audio-playback.md))
- [2025-04-22 21:30] Phase 1.3 Task 1-5: 接入 just_audio 音频播放基础设施 `feat: add just_audio playback service layer with source switching` ([entry](log/entries/2025-04-22-2130-add-just-audio-playback-service.md))
- [2025-04-22 20:00] 实现 LyricEditor 歌词编辑器与 Player 播放器 `feat: add lyric editor and player with synced lyrics` ([entry](log/entries/2025-04-22-2000-add-lyric-editor-and-player.md))
- [2025-04-22 19:25] 完成导入流程占位与 ProjectDetail 详情页 `feat: add import flow and project detail screen` ([entry](log/entries/2025-04-22-1925-add-import-flow-and-project-detail.md))
- [2025-04-22 19:15] 添加 ProjectRepository 抽象与内存实现 `feat: add project repository with memory implementation` ([entry](log/entries/2025-04-22-1915-add-project-repository-memory-impl.md))
- [2025-04-22 19:05] 接入 AppTheme 和 AppRouter，完成 Dashboard 产品入口 `feat: wire up theme and router, build dashboard entry point` ([entry](log/entries/2025-04-22-1905-wire-theme-router-dashboard.md))

## 2026-10-09 | Lyric timeline, LRC export and KTV microphone

- [2026-10-09 15:42] 持久化 KTV 麦克风输入设备选择 `Persist KTV microphone input choice` ([entry](log/entries/2026-10-09-1542-persist-ktv-microphone-input-choice.md))
- [2026-10-09 15:08] KTV 麦克风设备选择接入控制面板 `Expose KTV microphone device picker` ([entry](log/entries/2026-10-09-1508-ktv-microphone-device-picker.md))
- [2026-10-09 14:59] 增加 KTV 麦克风输入设备枚举与热切换底层 `Add KTV microphone input device switching` ([entry](log/entries/2026-10-09-1459-ktv-microphone-input-device-switching.md))
- [2026-10-09 12:58] 打通 KTV 人声录音、对齐保护与离线混音导出 `Add aligned KTV take recording and mix export` ([entry](log/entries/2026-10-09-1258-aligned-ktv-take-recording-and-mix-export.md))
- [2026-10-09 12:36] 接入 KTV 实时麦克风监听、独立音量与延迟控制 `Add low-latency KTV microphone monitoring` ([entry](log/entries/2026-10-09-1236-low-latency-ktv-microphone-monitoring.md))
- [2026-10-09 12:14] 增加播放器麦克风 KTV 入口与伴唱模式 `Add microphone KTV entry and backing choice` ([entry](log/entries/2026-10-09-1214-microphone-ktv-entry-and-backing-mode.md))
- [2026-10-09 12:03] 固定 LRC 导出的有效播放时间语义 `Export LRC with effective playback timestamps` ([entry](log/entries/2026-10-09-1203-lrc-effective-playback-timestamps.md))
- [2026-10-09 11:57] 让播放器返回校对后立即读取最新歌词 `Refresh player lyrics after timeline editing` ([entry](log/entries/2026-10-09-1157-refresh-player-lyrics-after-edit.md))
- [2026-10-09 11:52] 让普通同步歌词随播放自动滚动 `Auto-scroll synced lyrics with playback` ([entry](log/entries/2026-10-09-1152-auto-scroll-synced-lyrics.md))
- [2026-10-09 11:46] 打通歌词时间轴校对与 LRC 导出切片 `Add synced lyric timeline editing and LRC export` ([entry](log/entries/2026-10-09-1146-synced-lyric-timeline-and-lrc-export.md))

## 2026-10-19 | ASR model download, proxy and setup

- [2026-10-19 16:11] 允许代理独立保存并在对话框内提示缺项 `Allow saving ASR proxy independently` ([entry](log/entries/2026-10-19-1611-save-asr-proxy-independently.md))
- [2026-10-19 15:55] 立即持久化安装流程中的高级识别设置 `Persist ASR advanced settings immediately` ([entry](log/entries/2026-10-19-1555-persist-asr-advanced-settings-immediately.md))
- [2026-10-19 15:44] 为 ASR 模型下载接入代理与连通性检查 `Add proxy support for ASR downloads` ([entry](log/entries/2026-10-19-1544-asr-download-proxy-and-connectivity-check.md))
- [2026-10-19 15:30] 区分 ASR 环境准备与文件下载进度 `Clarify ASR setup and download progress` ([entry](log/entries/2026-10-19-1530-asr-setup-vs-download-progress.md))
- [2026-10-19 15:17] 修复 ASR 模型下载超时与自动续传 `Retry stalled ASR model downloads` ([entry](log/entries/2026-10-19-1517-retry-stalled-asr-model-downloads.md))

## 2026-10-19 | Lyric association and playback queue

- [2026-10-19 23:52] 编辑器进度条与播放位置插入歌词行 `Editor seek and insert line at playback` ([entry](log/entries/2026-10-19-2352-editor-seek-and-insert-line-at-playback.md))
- [2026-10-19 23:05] 制定歌词校对与时间轴开发计划 `Add lyric review alignment development plan` ([entry](log/entries/2026-10-19-2305-lyric-review-alignment-plan.md))
- [2026-10-19 22:28] 统一各播放面的歌词可用性判定 `Unify playback lyrics availability across surfaces` ([entry](log/entries/2026-10-19-2228-unify-playback-lyrics-availability.md))
- [2026-10-19 21:22] 入队时同步歌词状态，统一各播放面判定 `Sync lyrics flag into playback queue enrichment` ([entry](log/entries/2026-10-19-2122-sync-lyrics-flag-into-playback-queue.md))
- [2026-10-19 20:58] 收尾歌词首次写入工程的自动关联切片 `Auto-link lyrics on first project save` ([entry](log/entries/2026-10-19-2058-auto-link-lyrics-on-first-project-save.md))
- [2026-10-19 20:33] 歌词关联三级解析与死链自愈 `Add fallback resolution and self-healing for lyric links` ([entry](log/entries/2026-10-19-2033-lyric-link-fallback-resolution-and-self-healing.md))
- [2026-10-19 16:48] 修复识别歌词未关联到本地歌曲 `Link transcribed lyrics to local songs` ([entry](log/entries/2026-10-19-1648-link-transcribed-lyrics-to-local-songs.md))

## 2026-10-19 | Work log harness

- [2026-10-19 22:09] 解锁全项目分析器与全量测试 `Unblock analyzer and full test suite` ([entry](log/entries/2026-10-19-2209-unblock-analyzer-and-test-suite.md))
- [2026-10-19 21:58] 为工作日志流程增加跨平台校验工具 `Add work log lint tool and quality gate hook` ([entry](log/entries/2026-10-19-2158-work-log-lint-tool.md))
- [2026-10-19 21:41] 工作日志改为条目单文件化并补回丢失记录 `Move work log entries to per-task files` ([entry](log/entries/2026-10-19-2141-work-log-entry-per-file-model.md))


## 2026-10-19 | Lyric review and alignment pipeline

- [2026-10-19 23:24] 修复播放进度条拖动并统一时间显示 `Fix draggable playback progress bar with time labels` ([entry](log/entries/2026-10-19-2324-fix-draggable-playback-progress-bar.md))
- [2026-10-19 23:38] 全播放界面进度条支持悬停、点击与拖动跳转 `Make playback progress bars seekable with hover time hints` ([entry](log/entries/2026-10-19-2338-seekable-progress-bars-everywhere.md))
- [2026-10-20 00:16] 参考歌词行级序列对齐服务 `Add reference lyric alignment service` ([entry](log/entries/2026-10-20-0016-reference-lyric-alignment-service.md))
- [2026-10-20 00:39] 参考歌词纠正入口与批量应用 `Add reference lyric correction entry and apply flow` ([entry](log/entries/2026-10-20-0039-reference-lyric-alignment-entry-and-apply.md))
- [2026-10-20 11:53] 参考歌词逐行确认（C3） `Add per-line reference lyric review` ([entry](log/entries/2026-10-20-1153-reference-alignment-per-line-review.md))
- [2026-10-20 12:28] 对齐备份恢复 UI `Add reference alignment backup restore flow` ([entry](log/entries/2026-10-20-1228-reference-alignment-backup-restore.md))
- [2026-10-20 13:25] 清理分析器提示信息 `Clear analyzer lint infos` ([entry](log/entries/2026-10-20-1325-clear-analyzer-lint-infos.md))
- [2026-10-20 15:01] 参考歌词补全漏行与推断时间轴 `Add reference lyric missing-line completion` ([entry](log/entries/2026-10-20-1501-reference-lyric-completion.md))
- [2026-10-20 15:04] 同步参考补全文案 `Clarify reference lyric completion copy` ([entry](log/entries/2026-10-20-1504-reference-completion-copy.md))
- [2026-10-20 20:30] 进度条与编辑保护修复（E1） `Fix progress bar single seek on release and manual-edit index drift after batch completion` ([entry](log/entries/2026-10-20-2030-e1-progress-bar-edit-protection.md))
- [2026-10-20 20:42] 新增歌词时间轴校验器（E2.1） `Add lyric timeline validator for conflict detection and calibration marking` ([entry](log/entries/2026-10-20-2042-e1-timeline-validator.md))
- [2026-10-20 20:48] 插入行与音频文件边界校验（E2.2） `Guard lyric insertion and audio track bounds` ([entry](log/entries/2026-10-20-2048-e2-insertion-audio-boundary.md))
- [2026-10-20 20:56] 完善 LRC 时间戳冲突处理（E2.3） `Report LRC timestamp import conflicts via LyricImportResult.conflicts` ([entry](log/entries/2026-10-20-2056-e2-lrc-conflict.md))
- [2026-10-21 00:35] 对齐服务区分匹配/自动替换阈值并引入低置信与歧义状态（E3.1） `Distinguish alignment match and auto-replace thresholds with low-confidence and ambiguous states` ([entry](log/entries/2026-10-21-0035-e3-alignment-threshold-states.md))
- [2026-10-21 01:28] 审核界面支持歧义匹配的替换或插入漏行判断（E3.3） `Review UI supports ambiguous match replace-or-insert-missing-line choice` ([entry](log/entries/2026-10-21-0128-e3-review-ambiguous-choice.md))
- [2026-10-21 01:35] 歌词对齐回归样本测试集（E3.4） ([entry](log/entries/2026-10-21-0135-e3-regression-sample-set.md))
- [2026-10-21 11:31] 歌词行稳定标识 LyricLine.id（E4.1） `Add stable line identity field to LyricLine` ([entry](log/entries/2026-10-21-1131-e4-line-id.md))
- [2026-10-21 11:45] 手工编辑保护标记跨会话持久化（E4.2） Persist manual-edit markers by stable line identity ([entry](log/entries/2026-10-21-1145-e4-marker-persistence.md))
- [2026-10-21 11:54] 参考对齐溯源语义与保存重开验证（E4.3） Record reference alignment provenance with stable line ids ([entry](log/entries/2026-10-21-1154-e4-alignment-provenance.md))
- [2026-10-21 12:26] 修复参考歌词对话框内 LayoutBuilder 导致的卡死 Fix reference alignment dialog freeze caused by LayoutBuilder in AlertDialog ([entry](log/entries/2026-10-21-1226-reference-dialog-layout-freeze.md))
- [2026-10-21 14:03] 参考歌词对齐：安全批量、时间来源与内存撤销 `Harden reference lyric alignment batch apply, timing provenance, and undo` ([entry](log/entries/2026-10-21-1403-reference-alignment-safe-batch-and-undo.md))
- [2026-10-21 15:47] 对齐后逐行对比与保守时间轴自动修复（PR #125） `Add post-apply lyric diff view and conservative timeline auto-repair` ([entry](log/entries/2026-10-21-1547-post-apply-diff-and-timeline-auto-repair.md))


## 2026-10-21 | Guided lyric review and audition

- [2026-10-21 16:50] 智能歌词复核优先队列（PR #126） ([entry](log/entries/2026-10-21-1650-smart-lyric-review-queue.md))
- [2026-10-21 17:04] 智能复核逐项完成与确认记录 ([entry](log/entries/2026-10-21-1704-guided-smart-review-confirmation.md))

<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->
## Additional archived entries (auto-generated)
- [2026-10-28 19:40] Bound forced-alignment HTTP request lifetimes `fix: bound forced-alignment HTTP request lifetimes (#213)` ([entry](log/entries/2026-10-28-1940-bound-forced-alignment-http-lifetimes.md))
- [2026-10-28 18:18] Bound Qwen transcription request and child process lifetimes `fix: bound Qwen transcription request and child process lifetimes (#212)` ([entry](log/entries/2026-10-28-1818-bound-qwen-transcription-lifetimes.md))
- [2026-10-28 17:45] Bound Whisper CLI process lifetimes `fix: bound Whisper CLI process lifetimes` ([entry](log/entries/2026-10-28-1745-bound-whisper-cli-process-lifetimes.md))
- [2026-10-28 16:40] Add recoverable atomic JSON persistence ([entry](log/entries/2026-10-28-1640-recoverable-json-persistence.md))
- [2026-10-28 13:45] Fix macOS Release Media Hub network entitlement `fix: enforce macOS Release Media Hub network entitlement` ([entry](log/entries/2026-10-28-1345-fix-macos-release-network-entitlement.md))
- [2026-10-28 13:39] Reframe roadmap around open-source product quality ([entry](log/entries/2026-10-28-1339-reframe-product-quality-roadmap.md))
- [2026-10-28 13:30] Incorporate second engineering review into readiness roadmap ([entry](log/entries/2026-10-28-1330-second-review-commercial-readiness.md))
- [2026-10-28 12:35] Verify engineering review findings and record deferred risks ([entry](log/entries/2026-10-28-1235-verify-engineering-review-risks.md))
- [2026-10-28 02:35] Add paired A/B evaluation for shared ASR preprocessing ([entry](log/entries/2026-10-28-0235-asr-preprocessing-ab-evaluator.md))
- [2026-10-27 19:20] Share one normalized audio input across ASR engines ([entry](log/entries/2026-10-27-1920-share-normalized-asr-input.md))
- [2026-10-27 18:54] Unify audio normalization across local ASR paths ([entry](log/entries/2026-10-27-1854-unify-asr-audio-normalization.md))
- [2026-10-27 17:54] Derive ASR model identities from runtime configuration ([entry](log/entries/2026-10-27-1754-derive-asr-model-identities.md))
- [2026-10-27 17:07] Require reproducible ForcedAligner evaluation provenance ([entry](log/entries/2026-10-27-1707-strict-forced-alignment-provenance.md))
- [2026-10-27 16:10] Require complete provenance for auditable ASR evaluation ([entry](log/entries/2026-10-27-1610-require-strict-asr-provenance.md))
- [2026-10-27 15:46] Track provenance for paired ASR evaluation ([entry](log/entries/2026-10-27-1546-track-asr-evaluation-provenance.md))
- [2026-10-27 12:06] Report ASR insertions, omissions, and substitutions ([entry](log/entries/2026-10-27-1206-report-asr-edit-breakdown.md))
- [2026-10-27 00:18] Preserve novel secondary ASR lines inside overlapping segments ([entry](log/entries/2026-10-27-0018-preserve-overlapping-asr-lines.md))
- [2026-10-27 02:50] Add a paired transcript evaluator for ASR engines ([entry](log/entries/2026-10-27-0250-add-asr-transcript-evaluator.md))
- [2026-10-26 22:50] Sync V2 audition fix with current mainline ([entry](log/entries/2026-10-26-2250-sync-v2-audition-main.md))
- [2026-10-26 21:30] Clarify ASR smoke-test scope versus lyric accuracy ([entry](log/entries/2026-10-26-2130-clarify-asr-smoke-test-scope.md))
- [2026-10-26 21:10] Make V2 lyric audition diagnosable and support timing A/B ([entry](log/entries/2026-10-26-2110-fix-v2-audition-feedback.md))
- [2026-10-26 20:35] Improve ASR fusion recall and confidence handling ([entry](log/entries/2026-10-26-2035-improve-asr-fusion-recall.md))
- [2026-10-26 20:00] Disable MPV on-disk packet cache for audio playback ([entry](log/entries/2026-10-26-2000-disable-mpv-disk-cache.md))
- [2026-10-26 18:20] Avoid unsupported OSC property in audio-only MPV adapter ([entry](log/entries/2026-10-26-1820-avoid-mpv-osc-property.md))
- [2026-10-26 18:00] Defer route observer notifications until after build ([entry](log/entries/2026-10-26-1800-route-observer-post-frame-sync.md))
- [2026-10-26 16:50] Capture local ForcedAligner results into evaluation corpus ([entry](log/entries/2026-10-26-1650-forced-align-local-capture.md))
- [2026-10-26 16:35] Add repeatable ForcedAligner quality evaluation ([entry](log/entries/2026-10-26-1635-forced-align-quality-evaluation.md))
- [2026-10-26 16:20] Surface ForcedAligner coverage diagnostics in review ([entry](log/entries/2026-10-26-1620-surface-forced-align-diagnostics.md))
- [2026-10-26 16:15] Recover ForcedAligner line matches with bounded diagnostics ([entry](log/entries/2026-10-26-1615-forced-align-recovery-diagnostics.md))
- [2026-10-26 15:30] Normalize multilingual forced-alignment text matching ([entry](log/entries/2026-10-26-1530-normalize-forced-align-text.md))
- [2026-10-26 15:12] Represent unavailable ForcedAligner confidence honestly ([entry](log/entries/2026-10-26-1512-unknown-forced-align-confidence.md))
- [2026-10-26 15:05] Expose token-level forced alignment audition in proofreading ([entry](log/entries/2026-10-26-1505-audition-forced-align-tokens.md))
- [2026-10-26 14:30] Harden work-log lint and quality-gate feedback ([entry](log/entries/2026-10-26-1430-harden-work-log-ci.md))
- [2026-10-26 14:00] Wire ForcedAligner into the visible proofreading flow ([entry](log/entries/2026-10-26-1400-wire-forced-align-proofread-ui.md))
- [2026-10-25 21:55] Wire forced alignment into proofreading proposals ([entry](log/entries/2026-10-25-2155-wire-forced-align-proofread-service.md))
- [2026-10-25 19:48] Add native arbitrary-text forced-alignment endpoint ([entry](log/entries/2026-10-25-1948-add-native-forced-align-endpoint.md))
- [2026-10-25 17:05] Attach forced-alignment evidence to proofreading proposals ([entry](log/entries/2026-10-25-1705-forced-alignment-evidence-proposals.md))
- [2026-10-25 16:10] Add explicit forced-alignment HTTP adapter contract ([entry](log/entries/2026-10-25-1610-forced-alignment-http-adapter-contract.md))
- [2026-10-25 15:30] Add timestamped secondary ASR input to proofreading ([entry](log/entries/2026-10-25-1530-add-secondary-asr-transcript-input.md))
- [2026-10-25 13:56] Cover proofreading v2 review boundaries ([entry](log/entries/2026-10-25-1356-cover-proofread-v2-review-boundaries.md))
- [2026-10-25 02:25] Fix Qwen eager attention matmul layout ([entry](log/entries/2026-10-25-0225-fix-qwen-eager-attention-layout.md))
- [2026-10-25 00:55] Clarify failed ASR progress and copy diagnostics ([entry](log/entries/2026-10-25-0055-fix-asr-failure-progress-diagnostics.md))
- [2026-10-24 22:30] Recover Qwen downloads when source metadata differs ([entry](log/entries/2026-10-24-2230-fix-qwen-source-metadata-mismatch.md))
- [2026-10-24 21:30] Verify all required ASR model sources before installation ([entry](log/entries/2026-10-24-2130-verify-asr-preflight-required-models.md))
- [2026-10-24 19:15] Exercise Qwen download HTTP fallback behavior ([entry](log/entries/2026-10-24-1915-exercise-qwen-download-http-behavior.md))
- [2026-10-24 18:00] Validate ModelScope manifest as part of source preflight ([entry](log/entries/2026-10-24-1800-modelscope-source-preflight.md))
- [2026-10-24 17:50] Add official ModelScope fallback for managed Qwen model downloads ([entry](log/entries/2026-10-24-1750-modelscope-qwen-download-fallback.md))
- [2026-10-24 15:58] Resolve proofreading v2 merge conflicts ([entry](log/entries/2026-10-24-1558-resolve-proofreading-v2-merge-conflicts.md))
- [2026-10-24 15:56] Preserve dual-engine intent when Qwen setup fails ([entry](log/entries/2026-10-24-1556-preserve-qwen-dual-engine-mode.md))
- [2026-10-24 13:08] Integrate proofreading v2 review UI ([entry](log/entries/2026-10-24-1308-integrate-proofread-v2-review-ui.md))
- [2026-10-24 02:00] Unify proofread pipeline invariant tests ([entry](log/entries/2026-10-24-0200-unify-proofread-pipeline-invariants.md))
- [2026-10-24 01:43] Detect partial structural alignment mismatches ([entry](log/entries/2026-10-24-0143-detect-partial-structural-alignment-mismatches.md))
- [2026-10-24 01:37] Repair work-log generation and legacy commit parsing ([entry](log/entries/2026-10-24-0137-sync-generated-work-log-navigation.md))
- [2026-10-24 01:10] Cover structural reference alignment mismatches ([entry](log/entries/2026-10-24-0110-cover-structural-reference-alignment.md))
- [2026-10-23 09:45] Prevent partial token alignment from inflating coverage ([entry](log/entries/2026-10-23-0945-prevent-partial-token-alignment-coverage.md))
- [2026-10-23 09:20] Reject malformed ASR timing evidence ([entry](log/entries/2026-10-23-0920-reject-malformed-asr-timing-evidence.md))
- [2026-10-23 02:34] Add universal Flutter quality gate ([entry](log/entries/2026-10-23-0234-universal-flutter-quality-gate.md))
- [2026-10-22 13:42] 对齐本地分支与 GitHub 上游并修复 sanitizer 编译错误 ([entry](log/entries/2026-10-22-1342-reconcile-local-with-github-upstream.md))
- [2026-10-22 12:58] 契约核对与歌词智能校对 V2 架构方案设计（T0） ([entry](log/entries/2026-10-22-1258-document-lyric-proofreading-v2-contracts.md))
- [2026-10-22 02:40] 行级试听边界控制与循环试听（阶段 I） ([entry](log/entries/2026-10-22-0240-bounded-lyric-line-audition.md))
- [2026-10-21 23:08] 修复参考对齐对比组件中的合并冲突标记 ([entry](log/entries/2026-10-21-2308-fix-merge-conflict-markers-in-alignment-comparison.md))
- [2026-10-21 22:22] Add inline audition to smart review rows ([entry](log/entries/2026-10-21-2222-smart-review-inline-audition.md))
<!-- END AUTO-GENERATED WORK LOG REFERENCES -->
