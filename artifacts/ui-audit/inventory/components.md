# UI 组件清单（C. 交付物）

> 证据类型：**静态代码审计**。统计口径：`lib/` 下 402 个 Dart 文件、111,648 行。
> 核心结论：**项目没有共享组件库目录**（无 `lib/core/widgets` 或 `lib/shared`）。除主题 token 外，几乎所有复合组件都是页面内私有类（`_PrivateClass`），导致同类组件大量重复实现。

## 0. 总览统计

| 指标 | 数量 | 说明 |
|---|---|---|
| 页面级 Screen | 24 个文件 | `*/presentation/screens/` |
| 功能 Widget 文件 | 76 个 | `*/presentation/widgets/` |
| `Icon(Icons.*)` 调用 | 305 处 | 使用 207 个不同 Material 图标 |
| IconButton | 111 处 | 另有 IconButton.filled/filledTonal 变体 |
| showDialog 调用点 | 57 处 / 44 文件 | 弹窗密度极高 |
| showModalBottomSheet | 11 处 | |
| SnackBar | 133 处 | 主要反馈手段 |
| Tooltip（widget+参数） | 19 + 145 处 | 桌面端覆盖尚可 |
| Semantics | **仅 2 处** | 无障碍标注几乎缺失 |
| 空/错误/加载私有类 | **17 个** | 无统一空状态组件 |

## 1. 重复实现热点（本次审计最重要的一致性发现）

### 1.1 封面/Artwork —— 12 套实现
| 组件 | 位置 | 备注 |
|---|---|---|
| `_Artwork` | dashboard_screen.dart:1391 | 渐变占位+Icons.album |
| `_Artwork` | local_library_explorer_screen.dart:1014 | |
| `_CatalogArtwork` | local_artist_album_browser_screen.dart:857 | |
| `_CollectionArtwork` | local_collections_screen.dart:1195 | |
| `_PlaybackArtwork` | now_playing_screen.dart:503 | |
| `_ProjectArtwork` | player_screen.dart:1152 | |
| `_ProjectArtwork` | project_detail_screen.dart:655 | 同名不同实现 |
| `_Artwork` | quick_play_screen.dart:926 | |
| `_Artwork` | global_player_bar.dart:434 | |
| `_MobileArtwork` | mobile_global_player_bar.dart:200 | |
| `_QueueArtwork` | playback_queue_panel.dart:335 | |
| `RemoteMediaArtwork` | transfer/widgets/remote_media_artwork.dart:11 | 唯一公共组件，但只服务传输域 |

**影响**：圆角、占位图标、占位渐变、加载失败回退若有差异无法统一修正；同一首歌在 5 个页面可能呈现 5 种占位样式。**建议收敛为 1 个 `AppArtwork`。**

### 1.2 播放控制条 —— 4 套实现
`_TransportControls`(now_playing)、`_TransportPane`+`_PlaybackControls`(player_screen 两套！)、`_Transport`(quick_play)。
同一页面 player_screen 内部就存在 `_TransportPane`（592 行）与 `_PlaybackControls`（1246 行）两个类。

### 1.3 徽标/胶囊/状态标签 —— 15 套实现
`_MetaChip`(dashboard)、`_FeaturePill`(import)、`_Badge`×2(review_inbox + reference_alignment_review 同名私有）、`LyricTinyBadge`(atoms)、`_WordChip`、`_InfoChip`×2(now_playing + quick_play 同名）、`_CurrentBadge`、`_MetricChip`、`_StatusPill`、`_MiniPill`、`_StagePill`、`_CountPill`、`_StatusBadge`。
样式（padding、圆角、字号、色底 alpha）各自为政。**建议收敛为 `AppBadge`（status 枚举驱动）。**

### 1.4 空状态/错误/加载 —— 17 套私有实现
`_EmptyCard`、`_EmptyLyricsState`、`_NoResults`、`_EmptyLibrary`、`_EmptyNowPlaying`、`_NoLyricsState`、`_EmptyPlayer`、`_EmptyQueue`、`_EmptyQueueState`、`_Message`(review_inbox)、`_ErrorCard`(transfer)、`_LoadingState`×2、`_ErrorState`×2、`_LoadingBlock`、`_LoadingCard`。
图标尺寸（34/42/56/64）、间距、按钮样式（Filled/Outlined/TextButton 混用）均不统一。

## 2. 分类组件清单

### 2.1 导航组件
| 组件 | 位置 | 用途 | 评价 |
|---|---|---|---|
| AppNavigationShell | core/navigation/app_navigation_shell.dart | 顶层导航外壳 | 良好 |
| AppNavigationRail | 同上 | 宽屏侧边导航 | 良好；品牌位用原生图标（问题 B-01） |
| AppBottomNavigation | 同上 | 窄屏底部导航 | 良好 |
| `_SectionStrip` | local_music_library_shell.dart | 音乐库 5 分区 ChoiceChip 条 | 良好 |

### 2.2 音频控制组件
| 组件 | 位置 | 用途 | 评价 |
|---|---|---|---|
| SeekableProgressBar | player/widgets/seekable_progress_bar.dart | 可拖拽进度条 | 被 4+ 页面复用，良好；内含唯一硬编码 `Color(0x66000000)`(331 行） |
| PlaybackModeControls | player/widgets/playback_mode_controls.dart | 循环/随机 | 复用良好 |
| PlaybackQueuePanel | player/widgets/playback_queue_panel.dart | 队列面板 | 良好 |
| KtvRecordingToolbar / KtvControlLabel | player/widgets/ktv_*.dart | KTV 录音工具条 | 领域专用 |
| GlobalPlayerBar / MobileGlobalPlayerBar | player/widgets/ | 常驻播放条 | 桌面/移动两套，合理 |

### 2.3 歌词编辑器组件族（34 个文件）
| 组件 | 行数 | 用途 | 评价 |
|---|---|---|---|
| LyricEditorToolbar | 550 | 工具条（播放/筛选/跟随/偏移/校对菜单） | 已重构收敛（原 20+ 控件），结构合理 |
| LyricProofreadMenuButton | 377 | **20 个校对工具的单一菜单入口** | 收敛方向正确，但单菜单 20 项过载（问题 C-02） |
| LyricEditorOverflowMenu | （toolbar 内） | 撤销/重做/插入/导出/播放器 | 合理 |
| LyricListPane | 1358 | 歌词行列表（内联编辑/搜索/试听） | 超大组件，职责重 |
| InspectorPane | 972 | 行检查器侧栏 | 大组件 |
| LyricRecognitionSummaryCard | — | 识别摘要卡 | 良好 |
| LyricEditShortcuts | — | Ctrl+S/Z/Y/H 快捷键 | 仅编辑器有快捷键，全局缺失（问题 A-03） |
| lyric_editor_atoms | 2 个原子 | LyricTinyBadge / LyricNudgeButton | "atoms" 名不副实，未形成共享层 |

### 2.4 识别/设置组件
| 组件 | 行数 | 评价 |
|---|---|---|
| AiTranscriptionSettingsSection | **1008** | 设置页核心，含模式下拉/迁移/删除/高级 ExpansionTile，单组件过重（问题 C-03） |
| AsrRuntimeSetupDialog | 981 | 安装向导对话框，体量巨大 |
| TranscriptionConfigDialog | 736 | 识别配置弹窗 |
| GlobalTranscriptionQueueBar | — | 桌面常驻队列条 |
| AsrEndToEndSmokeTestCard / DiagnosticsSettingsCard | — | 设置页卡片 |

### 2.5 传输组件
DesktopMediaTransferHubV2（桌面中枢，含 Overview/Pairing/WaitingForPairing/Direction/SharedTracks/Error 卡）、RemoteMediaArtwork（唯一共享 artwork）。

## 3. 组件复杂度评价（任务书 §5.3）

| 现象 | 证据 | 判断 |
|---|---|---|
| 单菜单 20 项 | LyricProofreadMenuButton 20 个回调 | **有价值但过载**：菜单分组仅靠 1 个 Divider，20 项 × (标题+副标题) 的菜单需要分组标题或二级分组 |
| 工具条曾 20+ 控件 | lyric_editor_toolbar.dart 头注释 | **已修复**（重构为 Wrap+溢出菜单），文档 docs/lyric_proofreading_ux_review.md 记录 |
| 设置项层级 | AiTranscriptionSettingsSection 1008 行 | 模式选择/存储迁移/模型管理/高级设置混在一卡，建议拆卡 |
| 重复确认 | 参考对齐备份恢复"需要使用前二次确认"、更换伴奏/人声确认、重新识别确认 | 确认路径合理；未发现过度确认 |

## 4. 过度封装 / 参数膨胀

- `LyricEditorContent`：构造函数 **44 个参数**（lyric_editor_content.dart:106-153）——编辑器的全部回调穿过一个 widget，属"上帝组件"边缘。考虑拆分或引入 controller。
- `LyricEditorToolbar`：21 个参数；`LyricListPane`：25+ 参数。属编辑器域的结构性耦合，功能上可工作，但测试与复用成本高。
