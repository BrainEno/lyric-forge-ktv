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
- 应用规则：只改 `text`、`confidence = 100`、保留原时间戳、多余行不动；应用前写单槽备份 `metadata['referenceAlignmentBackup']`，应用后写 `metadata['referenceAlignment']`（新增 `acceptedReferenceCount`、`overriddenManuallyEditedCount`、`skippedBySelectionCount`）。C3 时漏行只列入待处理清单、不自动插入；C4 起由用户在逐行确认里显式勾选补入。
- 确认完成后仍走既有 `_saveChanges` 整文档保存；用户取消则不写入。
- widget 测试覆盖 390×844 下的默认勾选、低置信跳过、手动编辑行解锁确认与返回结果。

验收：粘贴正确歌词 → 逐行确认 → 错字被纠正且时间轴不变；C3 时漏行进入待处理清单，C4 起可勾选补全；用户已改过的行不被静默覆盖；保存重开后溯源信息仍在。

规模：C1 约 250 行 + 测试；C2 实际约 900 行（对话框、应用规则与测试，已拆成独立文件避免继续膨胀编辑器）；C3 实际约 800 行（独立 UI、字符 diff、应用扩展与测试），仍作为一次 C3 提交。

### C3.1 对齐备份恢复 UI（已完成）

- 新增纯 Dart `ReferenceAlignmentRestoreService`：`probeBackup` 校验单槽备份 `metadata['referenceAlignmentBackup']`，按四类可区分原因返回失败（missing / invalidShape / corruptDocument / lineCountMismatch）；`restore` 用快照生成新 `LyricDocument`，不修改入参、不落盘。
- 恢复确认对话框 `reference_alignment_backup_dialog.dart`：展示备份时间、来源（paste/file，含来源文件路径）、格式、行数，并明确"将覆盖当前编辑中的歌词"警告；破坏性按钮文案"恢复并覆盖"（≥48dp）；紧凑宽度下内容可滚动。
- 编辑器入口与"参考歌词纠正"同区：仅当备份存在且可解析时显示（紧凑/短屏放 AppBar 图标，宽屏进工具栏）；确认后替换 `_editingDocument`、`_hasChanges = true`、清空会话级手动编辑索引集合、过滤器重置为"全部"、选中行夹取到合法范围；探测或解析失败用 SnackBar 说明"备份不可用/已损坏"，不修改文档。
- 恢复语义：写入 `metadata['referenceAlignmentRestore']` 溯源（restoredAt/backupCreatedAt/backupReason/backupLineCount/restoredLineCount）并删除备份键——单槽，恢复即消耗，不允许重复恢复旧快照；备份文档自带的旧 `referenceAlignment` 溯源保留；恢复后不自动保存，由用户显式保存落盘。
- 测试：服务单测 9 例（正常恢复、缺失、类型错误、JSON 损坏、行数不一致、备份键消耗、溯源字段、入参不可变、旧溯源保留）；widget 测试 5 例（390×844：无备份无入口、损坏备份无入口、摘要展示、取消不改文档、确认后替换并消耗备份）。

### C4 纯文本参考补全漏行与建立时间轴（已完成）

- 复用 C2 的"参考歌词纠正"入口和纯文本粘贴/文件解析：用户粘贴整段无时间戳歌词后，先走 C1 对齐，再对 `missing` 参考行生成插入计划。
- 新增纯 Dart `ReferenceTimelineCompletionService`：
  - 漏行插到后一个已匹配 ASR 行之前；没有后锚点时追加到末尾；连续漏行保持参考顺序；
  - 纯文本漏行在"前一个已匹配行的结束时间"和"后一个已匹配行的开始时间"之间平均分配，至少 10ms；末尾漏行从上一行结束时间起每行 5 秒；
  - 带时间戳的参考漏行优先使用参考时间；
  - 前后锚点之间夹着未匹配 ASR 行、或空隙不足时标记 `requiresConfirmation`，提示可能已被 ASR 合并/拆分。
- `ReferenceAlignmentApplier` 增加 `acceptedMissingReferenceIndices`：显式选中时按计划插入 `LyricLine(text, startTime, endTime)`，`confidence = 100`；不传或空集合保持旧行为（不插入）；文字纠正、时间轴替换和插入在同一份文档上一次完成，原有行不删除、不重排。
- 逐行确认 UI：漏行卡片展示插入位置、推断时间区间和"需确认"徽标；非歧义漏行默认勾选，歧义漏行默认不勾选；新增"补全全部漏行"快捷按钮，底部文案区分"补全"与"修正"。
- 编辑器应用后仍写单槽备份 `metadata['referenceAlignmentBackup']`，`metadata['referenceAlignment']` 增加 `acceptedMissingReferenceCount`、`insertedReferenceCount`、`skippedMissingReferenceCount` 和逐行 `insertions`（最终行索引、参考索引、起止时间、是否需确认）；新增/纠正后仍由用户显式保存。
- 测试：插入计划 9 例、应用器补行 4 例、逐行确认 widget 2 例（默认勾选非歧义漏行、歧义漏行需手动确认）。
- 限制：不做跨行重组；断句/合并差异会表现为"需确认"的漏行，默认不插入；插入不裁剪相邻行已有的结束时间，极端重叠需人工调整。

验收：粘贴整段无时间戳歌词 → 逐行确认中看到漏行及推断时间 → 应用后漏行按顺序插入且有可播放时间 → 保存重开后文字、顺序、时间与 `insertions` 溯源仍在。

规模：C4 约 600 行（服务、应用器扩展、UI、测试），作为一次提交。

## 阶段 E：对齐可靠性硬化（E1–E5，已完成）

E1–E4 解决了时间轴校验、LRC 冲突提示、阈值状态与歧义选择、稳定行标识与持久化保护。E5 在此基础上补齐"正确性优先"的批量采纳、时间来源溯源与可预览/可撤销的应用流程：

- **匹配与歧义（E5.1）**：行相似度仍为字符级 Levenshtein 比率，但配对分数改为 `similarity - 0.7`，弱匹配（相似度 ≤0.7）宁可让给两条 gap，落入漏行/多余行而不是强行替换；歧义判定改为前向/后向 DP 的全局证据，不再只看单行相似度。参考行与 ASR 行的一对多/多对一结构差异单独标记 `structuralMismatch`，不隐式合并或拆分，只能逐行确认。
- **时间轴诊断（E5.2）**：`LyricTimelineValidator` 新增重复开始时间、开始时间倒退、叠加全局偏移后的负开始时间、音频总时长边界检查，并新增 `compare(before, after)`，只把本次操作新引入的问题算作 `introduced`；严重的新冲突在应用前弹出"撤销本次对齐 / 保留并检查"明确选择，普通预览不受阻。
- **缺失行时间（E5.3）**：纯文本漏行按文字视觉长度加权分配前后锚点之间的空隙，末尾漏行标记 `estimatedTail` 并从上一行结束时间起按默认时长收尾；参考时间戳、ASR 映射、插值、末尾估算、手动校准分别记录为 `reference` / `mappedAsr` / `interpolated` / `estimatedTail` / `manual`，按稳定 `lineId` 写入 `metadata['timingProvenance']`，已有 `manual` 值不被覆盖。文字置信度与时间来源保持独立。
- **批量应用与撤销（E5.4）**：新增 `ReferenceAlignmentBatchSelector`，安全批量只含高置信、无歧义、无结构差异且非手动编辑的 `replace` 行；低置信、歧义、结构差异与受保护行进入"需确认"组，必须通过独立的"选择需确认行"入口显式确认。逐行确认界面按"可安全批量采纳 / 需逐行确认"分区，并展示导入冲突、修复警告与结构差异说明。应用后 SnackBar 提供内存撤销，恢复应用前文档、`globalOffset`、稳定行标识、手动编辑集合、选中行与未保存状态；撤销不写磁盘，任何后续编辑、保存或恢复备份都会使快照失效。只有用户显式保存才落盘。
- **导入冲突（E5.5）**：LRC 重复/倒退时间戳等冲突从导入服务原样传入 `ReferenceLyricInput.conflicts`，偏移造成的零时长修复写入 `warnings`，审核界面明确展示，不静默丢弃或改写用户参考文本。
- **阈值集中**：自动替换阈值统一引用 `LyricAlignmentService.defaultAutoReplaceThreshold`（默认 0.8），应用器与审核界面不再各自硬编码。

验收：歧义行与结构差异行不会被批量误采纳；应用前后时间轴冲突可区分；撤销可完整恢复应用前状态；保存重开后时间来源与手动保护仍按稳定行标识定位。

### E6 对齐后逐行对比与保守时间轴自动修复（已完成，PR #125）

- 应用参考对齐后、undo 快照有效期内，编辑器提供"查看逐行对比"：按稳定 `lineId` 对比应用前快照与当前文档，字符级 diff、时间变化与补全行一览，可复用当前播放会话试听某行；快照失效后入口禁用。
- 新增纯 Dart `LyricTimelineAutoRepairService`，在冲突对话框前先做三类保守修复：把"明确重叠"行的结束时间收紧到下一行开始时间；按已知音频总时长裁剪受影响行；在固定锚点之间按文字长度权重重新分配来源为估算（`interpolated`/`estimatedTail`）的插入行。参考/ASR/手动起始时间绝不移动，重复/倒退起始时间与放不下的估算行保持原样，继续由校验器报告。
- 修复行时间来源记为 `autoRepaired`（`metadata['timingProvenance']`），应用摘要提示"自动修复 N 处"；冲突对话框文案改为"自动修复后仍无法可靠推断"。

验收：`dart format`、`flutter analyze`、新增 10 例单测/widget 测试、`test/features/lyrics` 189/189、全量 523 通过、质量门通过（2026-10-21 本地完成）；真实窗口多视口复核仍待人工执行。

## 阶段 D（后续可选）：在线歌词搜索

- domain 定义 `LyricSearchProvider` 接口（`search(title, artist)` → 候选文本 + 来源）；data 层实现首个 provider（来源届时再定；注意非官方接口随时失效、版权风险，须遵守本地优先定位：搜索失败不影响离线流程；代理复用 ASR 下载的手动/环境/系统代理策略）。
- UI：C2 对话框增加"搜索"页签，选中结果进入同一条对齐确认流水线。
- 本轮不做，仅在 C2 的服务接口上预留挂载点。

## 顺序与依赖

- A 独立且小 → 先做；
- B 依赖 A 的共享进度条；
- C1 → C2 → C3 顺序推进；C2 的漏行补齐依赖 B（可先用"末尾追加"降级）；
- D 最后，仅留接口。

## 阶段 F：智能优先复核队列（Draft，验证待执行）

- 新增纯 Dart `LyricReviewPriorityService`，将已有证据合并为可解释的复核优先级：ASR 置信度、双引擎分歧、空歌词、低置信度重复词、疑似超长单行、异常时长和 `LyricTimelineValidator` 时间轴问题。
- 编辑器新增“智能复核”筛选，按优先级从高到低排序，并在行尾显示优先分值；悬停/长按可查看触发原因。队列为空时说明“暂未发现明显风险行”，不把启发式评分描述为正确率。
- 复核排序只使用本地现有元数据，不额外调用模型，不改写歌词或时间轴；高置信重复歌词不单独触发重复告警，降低副歌被误报的噪音。
- 验证待执行：`dart format`、新增优先级服务单测、`flutter analyze --no-pub`、全量歌词测试及真实窗口复核。Draft PR 不应在这些步骤通过前合并。

## 阶段 G：持久化人工复核决策与逐项完成流（Draft，验证待执行）

- 新增 LyricReviewDecisionService：以稳定 lineId 存储用户确认记录，并用文本 + 开始/结束时间的确定性指纹校验。行内容或时间变更后，旧确认自动失效并重新进入智能复核，不依赖行索引，因此插入/删除导致的索引位移不会串行。
- 编辑器检查器新增“确认本行无误并继续”和“取消已复核标记”；确认后自动切换到智能复核筛选，并选中剩余最高优先级行。队列为空时明确区分“本轮智能复核已完成”与“暂未发现明显风险行”。
- 复核决定写入文档 metadata，随现有显式保存流程持久化；不自动保存，不修改歌词文本或时间轴。用户编辑文本/时间后，由指纹机制要求重新确认。
- 队列滚动仅在筛选结果实际变化时回到顶部；避免每次播放进度刷新都将用户滚回列表顶部。智能复核模式暂时不跟随播放自动滚动，以免打断人工复核顺序。
- 验证待执行：新增复核决定服务单测与优先级队列回归测试；需运行格式化、定向测试、flutter analyze --no-pub、歌词模块和全量测试，以及多视口桌面人工检查。Draft 在通过本地验证前不应合并。

## 验证规范（每阶段收尾）

- `dart format` 变更文件；`flutter analyze`；相关 `flutter test`（对齐算法、共享控件、插入逻辑各配测试）；
- 涉及 UI 的阶段附手动清单：390×844、844×390、1024×768、1366×768、1600×900 视口，连续拖动进度条、KTV 录制锁定态、紧凑/展开布局切换不丢编辑状态。
