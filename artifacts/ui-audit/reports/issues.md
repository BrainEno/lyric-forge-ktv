# 问题总表（F. 交付物）

> 证据类型说明：本次全部问题来自**静态代码审计**（文件+行号可复核）；对比度为 WCAG 公式计算值；控件尺寸为代码 token 值。
> **无运行截图证据**（环境原因见 `environment-diagnostic.md`），"截图"列一律为"无（静态）"，不得视为已运行验证。
> 统计：**P0 × 0 · P1 × 4 · P2 × 18 · P3 × 21 · 合计 43**（2026-11-18 更正：T-01 由 P2 降为 P3）
> **当前状态见文末「处理状态（第 17 轮核对）」。**下面各表保留审计时的原始描述，只有部分行补了处理记录；一行没写“已完成”不代表还没处理。

## P1 —— 重大问题

| ID | 页面 | 类别 | 位置 | 现象 | 影响 | 实测/计算数据 | 截图 | 改进建议 | 优先级 |
|---|---|---|---|---|---|---|---|---|---|
| B-01 | 全局 | 视觉/品牌 | color_tokens.dart:29；assets/images/icon.png；app_navigation_shell.dart:108 | 图标=红/黑/米白+"F"+均衡器条；UI=Spotify 绿 #1DB954+深灰；导航品牌位用原生 graphic_eq 图标 | 产品零识别度，图标与 UI 像两个产品 | 图标已目视确认；accent 值硬证 | 无（静态） | 制定品牌映射方案（见总报告 §8），红色作为强行动/焦点锚点 | 高 |
| B-02 | 全局 | 品牌一致性 | app.dart:67；dashboard_screen.dart:333,291；settings_screen.dart:48 | **更正（2026-11-18）：**产品名是 Elysium Player。应用界面一直用 Elysium Player，README 和多份文档写的 LyricForge KTV 才是错的；审计时把方向判反了 | 文档与产品名不一致 | 4 处实证 | 无（静态） | 已按 D-030 把文档、导出标记和界面统一为 Elysium Player；LyricForge 只保留为目录名等内部标识。**第 10 轮：**用户确认模型目录 `D:\Models\LyricForge\ASRRuntime` 是真实路径；界面不再把它写成 “LyricForge ASRRuntime” 这样的名称，而是按平台写成路径（`LyricForge\ASRRuntime`）并给出完整示例 | 高 |
| A-01 | 全局 | 无障碍 | app_theme.dart elevatedButtonTheme、snackBarTheme | 白字 #FFF 于 accent #1DB954 之上 | 主按钮/SnackBar 文字对比度不足 | **计算 2.59:1**，AA 需 4.5:1 | 无（静态） | accent 压暗（如 #14833B 计算约 4.6:1）或按钮用黑字/深色底 | 高 |
| S-01 | 全局 | 视觉/字体 | app_theme.dart:195；pubspec.yaml fonts 段（全注释） | 声明 fontFamily:'Inter' 但未打包字体 | 设计意图从未生效；中英混排回退系统字体，跨平台字形不一致 | 实证：assets 无字体文件 | 无（静态） | 打包 Inter（OFL 许可）+ 配置 CJK fallback 链，或删除声明改用系统字 | 高 |

## P2 —— 一般问题

| ID | 页面 | 类别 | 位置 | 现象 | 影响 | 数据 | 截图 | 改进建议 | 优先级 |
|---|---|---|---|---|---|---|---|---|---|
| C-01 | Dashboard | 信息架构 | dashboard_screen.dart | 「打开音乐」入口 ×3（Header/Hero/区块 action） | 主操作稀释 | 3 处实证 | 无 | 收敛为 1 主入口 | 中 |
| C-02 | 歌词编辑器 | 组件复杂度 | lyric_proofread_menu_button.dart | 校对菜单 20 项仅 1 个分隔线 | 查找成本高，矮屏需滚动 | 20 项实证 | 无 | 分组标题+高频项前置 | 高 |
| C-03 | 设置 | 组件复杂度 | ai_transcription_settings_section.dart | 单组件 1008 行，模式/迁移/下载/高级混排 | 层级不清 | 行数实证 | 无 | 拆为 3–4 张卡 | 中 |
| C-04 | 全局 | 一致性 | 12 处 Artwork 实现（见 components.md §1.1） | 封面组件重复 | 占位样式不可统一 | 12 处实证 | 无 | 收敛 `AppArtwork` | 高 |
| C-05 | 全局 | 一致性 | 15 处 Badge/Pill/Chip 实现 | 状态标签各自为政 | 视觉漂移 | 15 处实证 | 无 | 收敛 `AppBadge` | 高 |
| C-06 | 全局 | 一致性 | 17 处空/错/加载私有类 | 空状态无规范 | 图标 34–64、按钮样式混用 | 17 处实证 | 无 | 收敛 `AppEmptyState` | 中 |
| C-07 | 播放器族 | 一致性 | now_playing:546、quick_play:997、player:592,1246 | 4 套传输控制 | 行为/样式漂移风险 | 4 处实证 | 无 | 收敛 `TransportBar` | 中 |
| N-01 | 路由 | 交互 | app_router.dart:82-108 | `/quick-play` 依状态渲染 3 种页面 | 入口预期不稳 | 实证 | 无 | 入口改名/拆分意图 | 中 |
| D-04 | Dashboard | 视觉 | dashboard_screen.dart:1382 | 最近播放卡不用真实封面 | 重复灰色占位，列表单调 | 实证（未传 path） | 无 | 接 artworkPath | 中 |
| L-01 | 音乐库 | 无障碍/交互 | local_music_library_shell.dart:143 | FAB.small=40dp < 项目自定 48dp | 触达不达标且遮内容 | Material 规格 40dp | 无 | 改标准尺寸或移入 strip | 中 |
| L-02 | 全局 | 信息架构 | 4 处传输入口 | 低频功能入口过多 | 界面噪音 | 实证 | 无 | 收敛至 1–2 处 | 中 |
| E-02 | 歌词编辑器 | 文案 | lyric_proofread_menu_button.dart | 「智能校对 V2」版本号外露等 | 用户需解码术语 | 实证 | 无 | 去版本号、统一命名 | 中 |
| I-01 | 导入 | 信息架构 | transcription_ready_import_screen.dart:165 | 第一阶段标题"批量导入"实为环境准备 | 预期错配 | 实证 | 无 | 改题「准备识别环境」 | 中 |
| SE-01 | 设置 | 信息架构 | settings_screen.dart vs app_destinations.dart:63 | 承诺"播放/识别/存储"实仅识别+诊断 | 找不到播放/存储设置 | 实证 | 无 | 分区化设置 | 中 |
| P-01 | 工程详情 | 一致性 | project_detail_screen.dart:695+ | 5 种 pill 组件同页 | 视觉噪音 | 实证 | 无 | 并入 AppBadge | 中 |
| K-01 | KTV 舞台 | 视觉/功能呈现 | fullscreen_ktv_lyric_stage.dart | 仅行级高亮，无逐字着色（静态推断，需运行确认） | KTV 核心体验平淡 | 代码未见逐字渲染 | 无 | 用已有逐字 timing 渲染 Karaoke 扫光。**已完成（2026-11-19）：**KTV 舞台按逐字时间扫光（工作日志 `2026-11-19-1115`）；第 10 轮补了全屏 KTV 的键盘控制、控件遮罩和统一错误状态 | 高 |
| A-02 | 播放器族 | 无障碍 | 全局 | 仅歌词编辑器有快捷键（Ctrl+S/Z/Y/H） | 桌面播放无空格/方向键 | 实证 | 无 | 全局播放快捷键 | 中 |
| A-03 | 全局 | 无障碍 | color_tokens.dart textTertiary | #6A6A6A 大量 12px 说明文字 | 弱视力可读性差 | **计算 3.46:1** < 4.5 | 无 | 提亮至 ≈#8A8A8A（计算 4.6:1） | 中 |

## P3 —— 细节问题

| ID | 页面 | 类别 | 位置 | 现象 | 数据 | 改进建议 | 优先级 |
|---|---|---|---|---|---|---|---|
| T-01 | 传输 | 工程/一致性 | remote_media_library_screen.dart | 632 行页面当前无路由入口（**更正：** 2026-11-03 工作日志记载其依赖包是"为将来装配而定义"的有意保留，且 workflow_screen_injection_contract_test 仍检查该文件） | 维护负担 | 无路由引用；有意保留 | 无 | 不删除；由维护者决定接入路由或正式下线 | 低 |
| D-06 | Dashboard | 工程债 | dashboard_screen.dart | 1623 行 21 私有 widget 单文件 | 实证 | 拆分 | 低 |
| E-03 | 歌词编辑器 | 视觉 | lyric_editor_toolbar.dart _StatusLine | 「待复核 N」用 accent 绿表"待办" | 实证 | 改用 warning 或中性色。**第 12 轮：**编辑器状态行早已改用 warning；校对收件箱的「待复核」徽标和参考歌词对齐的「待确认」也改为 warning，紫色只留给可点的东西 | 低 |
| E-04 | 歌词编辑器 | 工程债 | lyric_editor_content.dart:106 | 构造函数 44 参数 | 实证 | 状态对象化 | 低 |
| E-05 | 歌词编辑器 | 交互 | lyric_editor_content.dart:212 | 窄屏检查器 88% 高 sheet 遮上下文 | 88%/96% 实证 | 评估侧滑抽屉 | 低 |
| E-06 | 歌词编辑器 | 视觉 | lyric_editor_atoms.dart:41 等 | fontSize:10 硬编码小字 | 实证 | ≥11 或 token | 低 |
| L-03 | 音乐库 | 视觉 | local_music_library_shell.dart | chip 选中指示弱 | 实证 | 加选中下划线/强调 | 低 |
| L-05 | 音乐库 | 视觉 | local_library_explorer_screen.dart:939 | fontSize:11 硬编码 | 实证 | 走 TextTheme | 低 |
| P-02 | 工程详情 | 信息架构 | _ActionPanel | 人声/伴奏导入低频操作平铺 | 实证 | 收进"音频源管理" | 中 |
| P-03 | 工程详情 | 响应式 | _ProjectDetailContent | 宽屏单列可能留白过多（推断） | 推断 | 运行验证后评估双栏 | 低 |
| SE-02 | 设置 | 视觉 | settings_screen.dart:24,43 | AppBar 与正文双「设置」标题 | 实证 | 去正文标题 | 低 |
| SE-05 | 设置 | 信息架构 | settings_screen.dart:69 | 冒烟测试卡面向最终用户 | 实证 | 并入诊断/关于 | 低 |
| SE-06 | 设置 | 响应式 | settings_screen.dart:33 | 1920 宽单列留白（推断） | 推断 | 运行验证 | 低 |
| I-02 | 导入 | 视觉 | import_audio_screen.dart:272 | 卖点 pill 营销化 | 实证 | 收敛为一行副标 | 低 |
| R-01 | 校对收件箱 | 一致性 | review_inbox_screen.dart:207 | 固定歌词图标块，无封面 | 实证 | 接 AppArtwork | 低 |
| R-02 | 校对收件箱 | 信息架构 | 同上 | 已复核工程无归档 | 实证 | 过滤/折叠 | 低 |
| R-03 | 校对收件箱 | 效率 | review_inbox_screen.dart | 无批量操作（如全部标为已复核），需逐工程进入 | 实证 | 批量标记 + 撤销。**已完成：**每个工程的「更多操作」里有「全部标为已复核」；**第 11 轮：**汇总行加了全局的「全部工程标为已复核」，确认后逐个保存并显示进度，别处刚保存过的工程跳过不覆盖，结果一次可撤销 | 低 |
| R-04 | 路由 | 工程债 | app_router.dart default | 未知路由静默回首页 | 实证 | 加日志/提示 | 低 |
| T-02 | 传输 | 工程债 | transfer/*（8 屏 ~2900 行+命名 v2） | 子域体量 vs 频次不匹配 | 实证 | 文档化/简化。**第 10 轮：**手机端歌曲、艺人/专辑和下载管理三屏改用共享的错误横幅、加载和空状态（`transfer_list_states.dart`）。**第 13 轮：**桌面传输中心从 711 行拆成页面（约 360 行）、卡片（`desktop_transfer_hub_cards.dart`）和文案（`desktop_transfer_hub_text.dart`）；裸转圈改为说明在做什么的加载行，空曲库改为带「打开音乐库」「刷新电脑音乐库」的共享空状态，“电脑 Library”统一为“电脑音乐库”，地址列表显示“局域网 / Tailscale”而不是枚举名，手机上打开时给出“连接电脑”入口。**第 14 轮：**lyrics 下智能校对的 v2 文件和类名去掉了版本号（D-035） | 低 |
| S-04 | 歌词编辑器 | 主题 | lyric_proofread_v2_dialog.dart:692,802 | 评级色用 Material amber/green 绕 token | 实证 | 入 AppColors 语义色 | 低 |
| S-05 | 全局 | 主题 | 9 文件 13 处 | 圆角字面量未走 token | 实证 | 换 AppSpacing.radius* | 低 |
| A-04 | 全局 | 无障碍 | 全项目 | Semantics 仅 2 处 | 实证 | 核心控件补语义标注 | 低 |

## 按页面索引
- Dashboard：B-01/02、C-01、D-04、D-06
- 音乐库：L-01/02/03/05、C-04/06
- 播放器族：C-07、N-01、K-01、A-02
- 歌词编辑器：C-02、E-02/03/04/05/06、S-04
- 工程详情：P-01/02/03、C-05
- 设置：SE-01/02/05/06、C-03
- 导入：I-01/02
- 校对收件箱：R-01/02
- 传输：T-01/02
- 全局：B-01/02、A-01/02/03/04、S-01/04/05

## 处理状态（第 17 轮核对）

2026-11-30 按代码逐条核对，2026-12-01（第 14 轮）更新 T-02、E-02、E-04、E-06、S-04、S-05 六行，2026-12-02（第 15 轮）更新 C-03、E-04、A-04 三行，2026-12-03（第 16 轮）更新 A-04，2026-12-04（第 17 轮）补上只出现在页面报告里的十条（见本节第二张表）。“依据”是能在仓库里复核的位置：多数是代码里写明 `audit <ID>` 的注释，或替代掉问题的共享组件。仍然**没有**运行截图，“已处理”指代码层面，不代表在运行的应用里看过。

| ID | 状态 | 依据 |
|---|---|---|
| B-01 | 已处理 | `color_tokens.dart` 薰衣草紫 accent + Forge Red 只用于 `AppBrandMark`；导航品牌位用 `app_brand_mark.dart` |
| B-02 | 已处理 | D-030，见上表 |
| A-01 | 已处理 | accent 改为 #B69CFF，按钮文字用黑色 `onAccent`（9.2:1），`accent_palette_test.dart` 固定对比度 |
| S-01 | 已处理 | `app_theme.dart` 不再声明未打包的 Inter，使用系统字体 |
| C-01 | 已处理 | `dashboard_screen.dart`（audit C-01） |
| C-02 | 已处理 | 校对菜单按 `LyricProofreadGroup` 分组（`lyric_proofread_menu_button.dart`） |
| C-03 | 已处理 | 卡片拆到 `ai_transcription_settings_cards.dart`；第 15 轮把安装、暂停、识别已有模型、迁移和删除流程移到 `ai_transcription_settings_controller.dart`（`ChangeNotifier`，有单元测试），`ai_transcription_settings_section.dart` 从约 590 行降到约 240 行，只留需要 `BuildContext` 的对话框、目录选择和提示条 |
| C-04 | 已处理 | `core/widgets/app_artwork.dart` |
| C-05 | 已处理 | `core/widgets/app_badge.dart` |
| C-06 | 已处理 | `app_empty_state.dart`、`app_error_state.dart`、`app_loading_state.dart`；第 10、13 轮把传输页也换了过来 |
| C-07 | 已处理 | `player/presentation/widgets/transport_bar.dart` |
| N-01 | 已处理 | `core/navigation/playback_destination.dart` |
| D-04 | 已处理 | `dashboard_shelves.dart`（audit D-04） |
| L-01 | 已处理 | 小浮动按钮已移除，传输入口在分区条里（`local_music_library_shell.dart`） |
| L-02 | 已处理 | `core/navigation/transfer_entry.dart`：只剩两个入口，同名同图标 |
| E-02 | 已处理 | 菜单不再显示版本号（`reference_alignment_dialog.dart` 注释）；代码里的 v2 文件名和类名第 14 轮也去掉了（T-02、D-035） |
| I-01 | 已处理 | `import_step_indicator.dart`（audit I-01） |
| SE-01 | 已处理 | `settings_screen.dart` 的 `settingsIntro` 只写页面里真有的内容 |
| P-01 | 已处理 | `production_steps.dart`（audit P-01） |
| K-01 | 已处理 | 见上表 |
| A-02 | 已处理 | `global_playback_shortcuts.dart` |
| A-03 | 已处理 | `textTertiary` 提亮到 #8F8F8F |
| T-01 | 已处理 | `remote_media_library_screen.dart` 已下线，`workflow_screen_injection_contract_test.dart` 检查它不再存在 |
| T-02 | 已处理 | 手机端三屏（第 10 轮）、桌面传输中心（第 13 轮）；第 14 轮去掉智能校对的 v2 文件名和类名（D-035），`proofread_naming_test.dart` 防止回退 |
| D-06 | 已处理 | `dashboard_screen.dart` 从 1623 行拆到约 525 行，组件在 `home/presentation/widgets/` |
| E-03 | 已处理 | 见上表（第 12 轮） |
| E-04 | 已处理 | 参数按关注点分组（`lyric_editor_actions.dart`）；第 14 轮把复核队列和播放器的 13 个参数收成 `LyricReviewControls`、`LyricPlaybackControls`（`lyric_editor_review_controls.dart`），构造函数从 26 个参数降到 15 个，筛选、选中和播放行的规则有单元测试；第 15 轮工具栏、列表和右侧检查面板也直接接收这两个对象（`lyric_editor_panes_controls_test.dart`） |
| E-05 | 已处理 | `line_inspector_sheet.dart`（audit E-05） |
| E-06 | 已处理 | 第 14 轮 `labelSmall` 从 10 改为 11，小号徽章不再缩到 10；`text_theme_floor_test.dart` 要求主题字号不小于 11 |
| L-03 | 已处理 | `app_theme.dart` 选中 chip 填充（audit L-03） |
| L-05 | 已处理 | `local_library_explorer_screen.dart` 已无硬编码 `fontSize: 11` |
| P-02 | 已处理 | `project_audio_sources_section.dart`（audit P-02） |
| P-03 | 已处理 | `project_detail_columns.dart`（audit P-03），宽屏双栏 |
| SE-02 | 已处理 | `settings_screen.dart`（audit SE-02） |
| SE-05 | 已处理 | `asr_end_to_end_smoke_test_card.dart`（audit SE-05） |
| SE-06 | 已处理 | `settings_columns.dart`（audit SE-06），宽屏双栏 |
| I-02 | 已处理 | `import_audio_screen.dart`（audit I-02） |
| R-01 | 已处理 | `review_inbox_screen.dart`（audit R-01） |
| R-02 | 已处理 | 收件箱把已复核工程折叠成一组（`review_inbox_screen.dart`，audit R-02） |
| R-03 | 已处理 | 见上表（第 11 轮） |
| R-04 | 已处理 | `route_not_found_screen.dart`，未知路由不再静默回首页 |
| S-04 | 已处理 | `lyric_proofread_dialog.dart` 已不用 Material amber/green |
| S-05 | 已处理 | 第 14 轮核对：`lib` 里只剩两处 `CircleAvatar(radius: 24)`，已改用 `AppSpacing.avatarRadius`；`source_hygiene_test.dart` 拒绝 `circular(数字)`、`fontSize: 数字` 和 `radius: 数字` |
| A-04 | 已处理 | `Semantics` 从 2 处增加到约 30 处（如 `player_bar_semantics.dart`）。第 15 轮：编辑器每一行合成一个节点，读出行号、时间段、文字和状态，选中是真正的 selected 状态，双击/右键/长按才有的编辑都成了自定义操作（`lyric_row_semantics.dart`，D-036）；行内编辑的两个时间、逐字时间小块、全屏 KTV 也有了名字或操作。第 16 轮（D-037）：剩下 14 处没有名字的卡片和行（首页三处、导入两张卡、校对收件箱、播放页歌词、歌手/专辑/播放列表/歌曲卡、播放队列、后台解析条、手机端桌面曲库两处）都用 `core/widgets/app_tap_target.dart` 读成一个按钮：一句话标签、点按提示、禁用和当前状态，卡片里的 ⋯ 菜单和小按钮成了自定义操作；措辞放在各功能的 `*_semantics.dart`。审计脚本再扫一遍，`lib` 里 27 处 `InkWell`/`GestureDetector` 都有名字或在有名字的节点里（检查面板的拖动条只是改高度，旁边有关闭按钮）。“已处理”是代码层面：还没在 TalkBack/VoiceOver 上实际听过 |

### 只在页面报告里的条目（第 17 轮核对）

页面报告（`pages/*.md`）里有十条没进上面的总表。第 17 轮按代码逐条核对，并处理了 L-04 和 T-03（D-038）。

| ID | 状态 | 依据 |
|---|---|---|
| D-01 | 撤销 | 页面报告已更正：Elysium Player 就是产品名（D-030） |
| D-02 | 已处理 | 随 B-01、A-01：accent 从 Spotify 绿换成薰衣草紫（`color_tokens.dart` 注释），首页 hero 不再用绿色渐变 |
| D-03 | 已处理 | 随 C-01：「打开音乐」只在页头出现，而且只在正在播放、hero 显示当前歌曲时出现（`dashboard_screen.dart` 的 `_Header` 注释） |
| D-05 | 撤销 | 窗口标题 Elysium Player 是正确的产品名（D-030） |
| E-01 | 已处理 | 随 C-02、E-04：校对菜单按 `LyricProofreadGroup` 分成四组带标题（`lyric_proofread_menu_button.dart`） |
| I-03 | 未处理 | `asr_runtime_setup_dialog.dart` 仍有约 957 行；安装失败、进度和存储预检的三张卡已经是共享组件，设置页和弹窗都在用 |
| L-04 | 已处理 | 第 17 轮（D-038）：三个私有封面包装删掉，圆角和图标的选择放在 `AppArtwork`（`tileRadius`、`rowRadius`、`AppArtwork.person`、`AppArtwork.missing`）；四个目录网格共用 `core/widgets/app_catalog_card.dart`，`catalog_card_contract_test.dart` 防止回退 |
| SE-03 | 撤销 | 页面报告已更正，见 D-030 |
| SE-04 | 已处理 | 随 C-03：本地识别设置拆成区块（`ai_transcription_settings_section.dart`）、四张无状态卡（`ai_transcription_settings_cards.dart`）和流程（`ai_transcription_settings_controller.dart`） |
| T-03 | 已处理 | 文件名里的版本号第 14 轮已去掉（T-02、D-035）。第 17 轮（D-038）：手机端歌手 / 专辑卡用 `AppCatalogCard` 和同一套网格规则；`RemoteMediaArtwork` 用 `AppArtwork` 的边框和占位，歌手也是圆的；歌曲行的下载状态由 `RemoteTrackDownload` 一次推出。手机端歌曲行仍是自己的行布局，因为它有下载按钮和进度条 |
