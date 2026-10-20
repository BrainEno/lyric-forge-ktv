# Decisions

> 稳定决策的唯一存放处。任务细节在 `docs/log/entries/`，本文件只保留"仍然生效"的决定，
> 以及被取代但需要留痕的旧决定。新任务若推翻旧决定，请新增一条并把旧条目标记为「已取代」。

## D-001 导出的 LRC 使用烘焙后的有效播放时间

- 日期：2026-10-09
- 背景：不同播放器对 LRC `[offset:<ms>]` 正负方向解释不一致，导出的时间轴会在别的播放器上整体错位。
- 决定：导出时把工程 `globalOffset` 直接烘焙进每行时间戳，导出文件不再单独写 `[offset]`；工程 manifest 仍保留独立 offset 供编辑。
- 影响：跨播放器对齐一致；代价是重新导入后 offset 分解被压平，负的最终时间戳钳制到 `00:00.000`。
- 状态：生效
- 来源：[2026-10-09 12:03 条目](log/entries/2026-10-09-1203-lrc-effective-playback-timestamps.md)

## D-002 KTV 麦克风链路采用 record + flutter_soloud

- 日期：2026-10-09
- 背景：早期评估的 `audio_io >=0.3` 与现有 `mobile_scanner 7.4.x` 在 `web` 依赖上不可共存。
- 决定：改用 `record 6.2.1` 采集麦克风 PCM16、`flutter_soloud 5.1.2` 做低延迟输出，不降级扫码功能。
- 影响：保住 `mobile_scanner`；监听延迟只能"额外增加"补偿硬件既有延迟，UI 需如实展示 SoLoud 报告的输出延迟。
- 状态：生效
- 来源：[2026-10-09 12:36 条目](log/entries/2026-10-09-1236-low-latency-ktv-microphone-monitoring.md)

## D-003 ASR 下载代理只用手动/环境/系统静态配置

- 日期：2026-10-19
- 背景：Hugging Face 直连在部分网络下不可达，需要代理；同时必须避免引入未经验证的第三方镜像。
- 决定：按"手动 HTTP 代理 → 环境代理 → Windows/macOS 静态系统代理 → 直连"顺序解析；只支持无认证 HTTP 代理，不支持 SOCKS 与 PAC/WPAD 自动配置。
- 影响：代理可独立持久化到本地设置；检测到可识别的 PAC 设置时提示用户手动填写；镜像源不作为默认回退。
- 状态：生效
- 来源：[2026-10-19 15:44 条目](log/entries/2026-10-19-1544-asr-download-proxy-and-connectivity-check.md)

## D-004 工作日志条目单文件化，活动摘要由脚本生成

- 日期：2026-10-19
- 背景：`docs/work_log.md` 是多人/多分支共改的同一文件，"轮转即删行"这种破坏性编辑在合并时被整体覆盖过一次（`536a13d` 抹掉了三条已提交记录），索引也因此指向了不存在的条目。
- 决定：每条任务写一个独立条目文件 `docs/log/entries/<date>-<time>-<slug>.md`，写完永不移动、永不删除；`docs/work_log.md` 改为由 `dart tool/work_log.dart write` 生成的活动摘要（最近 8 条一行式），`dart tool/work_log.dart check` 负责校验摘要是否过期、归档条目是否被引用、索引快照日期与日志最新条目是否一致。
- 影响：条目正文不再参与合并冲突，轮转只影响几行摘要；代价是新增一个生成步骤，AGENTS.md 需标注该文件"勿手改"。校验实现选用 Dart 工具而非 PowerShell，以便在 Windows/macOS/Linux 复用并纳入 `flutter test`。
- 状态：生效
- 来源：本条目对应的任务条目

## D-005 歌词可用性以解析结果为准，队列标记只是缓存

- 日期：2026-10-19
- 背景：播放条目上的 `hasLyrics` 在入队时写入，歌词工程被删除或稍后生成时都不会自动更新，播放器底栏、快速播放与 Now Playing 会给出互相矛盾的"打开歌词 / 导入歌词"判断。
- 决定：`resolvePlaybackLyrics` 返回结构化的 `PlaybackLyricsResolution`（工程 id、是否真的带歌词、是否修复或清除死链），由 `resolveAndSyncPlaybackLyrics` 把权威结果经 `PlaybackSessionService.updateItem` 回写队列；应用壳层挂载 `PlaybackLyricsAvailabilitySync` 监听当前条目变化，各播放面继续同步读取回写后的标记，不各自重跑解析。远程流的标记由远端目录维护，不参与回写。
- 影响：死链清理与"入队后才生成歌词"两种情况都会收敛到同一判断；代价是每次切歌多一次内存内的解析（媒体元数据与工程列表均已缓存）。工程仓库读取异常仍被当作"没有工程"，属于既有硬化缺口。
- 状态：生效
- 来源：[2026-10-19 22:28 条目](log/entries/2026-10-19-2228-unify-playback-lyrics-availability.md)

## D-006 参考歌词纠正默认逐行确认，手动编辑需显式解锁

- 日期：2026-10-20
- 背景：C2 的 80% 阈值批量应用无法让用户在处理低置信行前看到字符级差异；直接覆盖本次手动改过的行也违反"不静默覆盖"。
- 决定：参考歌词纠正以逐行 diff 卡为默认入口；默认勾选相似度 ≥80% 且未手动编辑的行，低置信行需手动勾选；本次手动编辑过的行默认锁定，必须二次确认才能替换；时间轴是独立整体开关（参考与草稿 1:1、全部带时间戳、本次无手动编辑时开放）；漏行只列入待处理清单，不自动插入。
- 影响：C2 的摘要对话框被 C3 逐行确认取代；应用仍走显式保存，备份与溯源 metadata 保留；阈值自动采纳与显式选择在 `ReferenceAlignmentApplier` 中共存。
- 状态：生效
- 来源：[2026-10-20 11:53 条目](log/entries/2026-10-20-1153-reference-alignment-per-line-review.md)
