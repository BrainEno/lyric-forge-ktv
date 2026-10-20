# 歌词纠错与播放控制改进计划（参考歌词对齐 / 进度条拖动 / 定点插入）

> 2026-10-19 制定。目标：把"参考歌词纠错闭环、播放器进度条拖动与时间显示、暂停定点插入歌词行"
> 三件事拆成可独立验收、可分批提交的开发阶段。

## 背景与现状

- 歌词编辑器集中在 `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`（约 1800 行，`setState` 状态，无状态管理框架）。
- `LyricLine` 字段：`text` / `startTime` / `endTime` / `isChorus` / `confidence`；低置信 = `confidence < 70`（阈值散落：whisper 服务用 65，编辑器/config 用 70）。
- 已有双引擎互检（`HighQualityTranscriptionService` → `metadata['fallbackCandidates']`），编辑器有"备选候选"卡片可逐行采纳——参考歌词对齐的确认 UI 可沿用这一交互模式。
- 已有完整外部歌词导入服务 `LocalLyricFileImportService`（LRC/SRT/WebVTT/ASS/纯文本 + 多编码探测），但入口只在播放侧（`local_song_lyrics_import_action.dart`），编辑器内没有导入/对照入口；仓库内没有任何模糊对齐（编辑距离/序列对齐）代码。
- 进度条现状（探索结论）：
  - `now_playing_screen.dart`、`quick_play_screen.dart`：可拖动（`_dragValue` 模式，`onChangeEnd` 才 seek），有时间文本，正常。
  - `player_screen.dart` `_ProgressBar`（约 2821 行起，4 处使用，含 KTV 舞台层）：**不可用**——无本地拖动状态，`onChanged` 每个 tick 直接调 `onSeek`，父级又被 position 流高频重建，拖动时滑块被拉回实时位置；`duration` 未知时 `onChanged` 为 `null` 直接禁拖。
  - `immersive_ktv_screen.dart` `_ControlLayer`：同样模式，且**完全没有时间文本**。
  - 全局底栏（`global_player_bar.dart` / `mobile_global_player_bar.dart`）是 `LinearProgressIndicator`，纯显示，本轮不动。
  - KTV 录制锁定时用 `IgnorePointer` + 0.55 透明度禁拖（`player_screen.dart` 约 1884 行），该语义需保留。
- 编辑器已接 `PlaybackSessionService`：可播放/暂停、点行跳转、"从播放位置取起/止时间"（`_timelinePositionFromPlayback`，已含 globalOffset 处理），但没有进度条滑块；新增行只能追加到末尾（`_addNewLine`），无按时间/索引插入。
- 仓库目前没有"定时暂停/暂停在某时刻"能力；`PlaybackState.position` 为毫秒级、随 `positionStream` 更新，具备实现基础。
- 网络代码目前仅用于 ASR 模型下载（`AsrDownloadHttpClientFactory`，支持手动/环境/系统静态代理，见 D-003）。

## 已确认的产品决策（2026-10-19 与用户确认）

1. **歌词获取**：先做"粘贴/导入参考歌词 + 自动对齐"（离线、无版权/API 风险）；在线歌词搜索 API 作为后续可选阶段（阶段 D），本轮只留 provider 接口位置。
2. **纠正方式**：对齐结果逐行确认（diff 字符级高亮），支持批量应用高置信行；不静默覆盖用户已编辑歌词（AGENTS 既有规则）。
3. **时间轴**：参考歌词无时间戳时，按行对齐把 ASR 草稿的起止时间映射过去；ASR 漏掉的行按相邻行时间估算并标记"待校准"。带时间戳的 LRC 直接采用其时间戳（可整体 offset）。

## 阶段 A：播放进度条可拖动 + 时间显示（已完成）

问题根因：`player_screen._ProgressBar` 拖动时每 tick seek 且被 position 流重建拉回；`immersive_ktv_screen` 同样。底部固定播放条（`global_player_bar` / `mobile_global_player_bar`）是纯显示的 `LinearProgressIndicator`，完全不可交互；Now Playing / Quick Play 虽有拖动但缺少悬停时间提示。

改动（已完成）：

1. 新建共享控件 `lib/features/player/presentation/widgets/seekable_progress_bar.dart`：
   - 鼠标悬停显示光标处 `mm:ss` 气泡；按下立即 seek 到该位置；拖动时气泡与时间标签实时跟随，松手补一次最终位置；纯点击只 seek 一次。
   - 时长未知时显示 `--:--` 并禁拖；`enabled` 参数供 KTV 录制锁定复用。
   - `SeekableProgressBar.mini`：细轨道、无滑块/时间行，供底部固定播放条使用（桌面 14px、移动 28px 命中区）。
2. `player_screen.dart` 4 处、`immersive_ktv_screen.dart` 1 处替换为共享控件。
3. `now_playing_screen.dart`、`quick_play_screen.dart` 的私有进度条替换为共享控件，获得悬停/点击跳转。
4. `global_player_bar.dart`、`mobile_global_player_bar.dart` 的 `LinearProgressIndicator` 替换为 mini 变体，接入 `_session.seek`。

验收：拖动时滑块跟随手指、松手才 seek 一次；显示 `mm:ss` 时间；KTV 录制锁定仍禁拖；390×844、1024×768、1600×900 视口手测连续拖动。

规模：约 4 个文件、新增 200 行以内；配 1 个 widget 测试（拖动跟随、单次 seek、时间文本、禁用态）。

## 阶段 B：编辑器内进度条 + 暂停定点插入歌词行（已完成）

1. 编辑器工具栏接入阶段 A 的 `SeekableProgressBar`（悬停/点击/拖动 + 时间标签）；跳转前自动暂停，拖到目标时间后保持暂停。
2. "在播放位置插入"：`_insertLineAtPlayback()` 读取 `_timelinePositionFromPlayback()`（含 globalOffset），纯规则抽到 domain 层 `LyricTimelineInsertionService`：
   - 插入到第一行 `startTime > position` 之前（否则追加），保持时间序；
   - `end` 取下一行 `startTime`，无下一行时为 `start + 5s`；间隔不足 10ms 强制 10ms；
   - 新行文本为空、confidence 100；插入后清理按索引保存的复核元数据；
   - 插入后选中新行：双栏聚焦右侧文本框；紧凑布局自动打开行检查器并聚焦输入框；SnackBar 提示插入时间。
3. 按钮位置：Compact/Medium 进底部栏（图标 + 禁用态提示）；Expanded 及以上进工具栏（带文字按钮）。
4. 既有"添加歌词行"（末尾追加）保留；保存协议不变（整文档覆盖）。

验收：任意时间点暂停 → 插入 → 行序、时间正确、自动聚焦编辑、保存重开仍在；未开始试听时按钮禁用并提示先试听本工程。

规模：新增 domain service + 单测；`lyric_editor_screen.dart` 约 +150 行。

## 阶段 C：参考歌词对齐纠正（核心，C1→C2→C3 分三次提交）

### C1 对齐算法（domain 层，纯 Dart，无 Flutter 依赖，已完成）

- 新建 `lib/features/lyrics/domain/services/lyric_alignment_service.dart`：
  - 输入：ASR 草稿 `LyricDocument` + 参考歌词行列表（可带/不带时间戳）；
  - 归一化：去标点/空白/全半角/大小写后再比对；
  - 行级序列对齐（Needleman-Wunsch 或窗口化贪心），行相似度 = 字符级 Levenshtein 比率；
  - 输出 `LyricAlignmentResult`：每个参考行 → `{匹配的 ASR 行 index、相似度、映射起止时间、状态}`；ASR 行标记 `matched` / `将被纠正` / `unmatched`；
  - 特殊处理：重复段（`isChorus`）靠相邻行上下文约束避免重复行错配；空行、中英混排。
- 单测覆盖：错字行、整行漏识别、整行多余、纯中文/纯英文/中英混排、带时间戳参考（跳过对齐直接映射时间）。

### C2 入口与流程（presentation + data，已完成）

- 编辑器新增"参考歌词纠正"入口（宽屏工具栏按钮，紧凑/短屏放 AppBar 图标）→ 对话框：
  - 粘贴页签（LRC/SRT/WebVTT/ASS/纯文本自动判别）+ 文件页签（复用 `LyricFileImportService.importFile`，编码自动检测失败时可手动选 GBK 等）；
  - 可选歌名/艺术家输入（仅写入 metadata 做溯源，不做在线校验）；
  - 整体偏移（毫秒）叠加在 LRC `[offset:]` 标签之上，只作用于带时间戳的参考行，且不小于零。
- 纯文本走 C1 对齐并保留 ASR 时间轴；带时间戳的参考行在"与草稿一一对应"时可在摘要里勾选"同时采用参考时间轴"（默认勾选，应用后全局偏移归零），不满足一一对应则只纠正文字并说明原因。
- 对齐前把当前文档快照进 `metadata['referenceAlignmentBackup']`（单槽、快照里剔除该键防嵌套）；应用结果写 `metadata['referenceAlignment']`（来源、格式、相似度阈值、逐行相似度清单）。
- 新增 domain `ReferenceAlignmentApplier`：只改 `text`（`confidence = 100`）、保留原时间戳、漏行不插入、多余行不动、本次会话手动编辑过的行跳过（编辑器按会话维护行索引集，插入/删除时同步位移）。
- 结果摘要对话框：可纠正/完全一致/低相似/手动跳过/参考漏行/多余识别计数 + 前 5 行"旧→新"预览 + 漏行引导（用阶段 B 定点插入补齐）。（C3 起由逐行确认界面取代，摘要对话框已移除）

### C3 逐行确认 UI（已完成）

- 独立文件 `reference_alignment_review.dart`：逐行字符级 diff 卡片、单行采纳/跳过、顶部"全选高置信（阈值默认 80%）"、已选手动编辑行锁、参考漏行"待处理"清单、时间轴整体开关；底部"应用 N 行 / 采用参考时间轴"。
- 新增纯 Dart `CharacterDiffService`（按 Unicode 码点做 LCS，合并相邻片段；超长行退化为整行替换），配 10 个单测。
- `ReferenceAlignmentApplier` 增加 `acceptedReferenceIndices`：非 null 时按逐行选择应用，允许显式采纳低于阈值的行；`protectedLineIndices` 仍生效；新增 `skippedBySelectionIndices` 区分"用户跳过"与"低置信"。
- 时间轴是整体开关，与逐行文字选择独立；仍要求参考与草稿一一对应、全部行带时间戳且本次无手动编辑。
- 应用规则不变：只改 `text`、`confidence = 100`、保留原时间戳、漏行不插入、多余行不动；应用前写单槽备份 `metadata['referenceAlignmentBackup']`，应用后写 `metadata['referenceAlignment']`（新增 `acceptedReferenceCount`、`overriddenManuallyEditedCount`、`skippedBySelectionCount`）。
- 确认完成后仍走既有 `_saveChanges` 整文档保存；用户取消则不写入。
- widget 测试覆盖 390×844 下的默认勾选、低置信跳过、手动编辑行解锁确认与返回结果。

验收：粘贴正确歌词 → 逐行确认 → 错字被纠正且时间轴不变；漏行进入待处理清单；用户已改过的行不被静默覆盖；保存重开后溯源信息仍在。

规模：C1 约 250 行 + 测试；C2 实际约 900 行（对话框、应用规则与测试，已拆成独立文件避免继续膨胀编辑器）；C3 实际约 800 行（独立 UI、字符 diff、应用扩展与测试），仍作为一次 C3 提交。

## 阶段 D（后续可选）：在线歌词搜索

- domain 定义 `LyricSearchProvider` 接口（`search(title, artist)` → 候选文本 + 来源）；data 层实现首个 provider（来源届时再定；注意非官方接口随时失效、版权风险，须遵守本地优先定位：搜索失败不影响离线流程；代理复用 ASR 下载的手动/环境/系统代理策略）。
- UI：C2 对话框增加"搜索"页签，选中结果进入同一条对齐确认流水线。
- 本轮不做，仅在 C2 的服务接口上预留挂载点。

## 顺序与依赖

- A 独立且小 → 先做；
- B 依赖 A 的共享进度条；
- C1 → C2 → C3 顺序推进；C2 的漏行补齐依赖 B（可先用"末尾追加"降级）；
- D 最后，仅留接口。

## 验证规范（每阶段收尾）

- `dart format` 变更文件；`flutter analyze`；相关 `flutter test`（对齐算法、共享控件、插入逻辑各配测试）；
- 涉及 UI 的阶段附手动清单：390×844、844×390、1024×768、1366×768、1600×900 视口，连续拖动进度条、KTV 录制锁定态、紧凑/展开布局切换不丢编辑状态。
