# 问题总表（F. 交付物）

> 证据类型说明：本次全部问题来自**静态代码审计**（文件+行号可复核）；对比度为 WCAG 公式计算值；控件尺寸为代码 token 值。
> **无运行截图证据**（环境原因见 `environment-diagnostic.md`），"截图"列一律为"无（静态）"，不得视为已运行验证。
> 统计：**P0 × 0 · P1 × 4 · P2 × 19 · P3 × 20 · 合计 43**

## P1 —— 重大问题

| ID | 页面 | 类别 | 位置 | 现象 | 影响 | 实测/计算数据 | 截图 | 改进建议 | 优先级 |
|---|---|---|---|---|---|---|---|---|---|
| B-01 | 全局 | 视觉/品牌 | color_tokens.dart:29；assets/images/icon.png；app_navigation_shell.dart:108 | 图标=红/黑/米白+"F"+均衡器条；UI=Spotify 绿 #1DB954+深灰；导航品牌位用原生 graphic_eq 图标 | 产品零识别度，图标与 UI 像两个产品 | 图标已目视确认；accent 值硬证 | 无（静态） | 制定品牌映射方案（见总报告 §8），红色作为强行动/焦点锚点 | 高 |
| B-02 | 全局 | 品牌一致性 | app.dart:67；dashboard_screen.dart:333,291；settings_screen.dart:48 | 窗口标题、首页页头、设置副标、空态文案仍显示 "Elysium Player" | 用户看到的产品名与分发名（LyricForge KTV）不一致 | 4 处实证 | 无（静态） | 全局正名为 LyricForge KTV | 高 |
| A-01 | 全局 | 无障碍 | app_theme.dart elevatedButtonTheme、snackBarTheme | 白字 #FFF 于 accent #1DB954 之上 | 主按钮/SnackBar 文字对比度不足 | **计算 2.31:1**，AA 需 4.5:1 | 无（静态） | accent 压暗（如 #14833B 计算约 4.6:1）或按钮用黑字/深色底 | 高 |
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
| T-01 | 传输 | 工程/一致性 | remote_media_library_screen.dart | 632 行死代码页面 | 维护负担、误导 | 零引用实证 | 无 | 删除 | 低 |
| P-01 | 工程详情 | 一致性 | project_detail_screen.dart:695+ | 5 种 pill 组件同页 | 视觉噪音 | 实证 | 无 | 并入 AppBadge | 中 |
| K-01 | KTV 舞台 | 视觉/功能呈现 | fullscreen_ktv_lyric_stage.dart | 仅行级高亮，无逐字着色（静态推断，需运行确认） | KTV 核心体验平淡 | 代码未见逐字渲染 | 无 | 用已有逐字 timing 渲染 Karaoke 扫光 | 高 |
| A-02 | 播放器族 | 无障碍 | 全局 | 仅歌词编辑器有快捷键（Ctrl+S/Z/Y/H） | 桌面播放无空格/方向键 | 实证 | 无 | 全局播放快捷键 | 中 |
| A-03 | 全局 | 无障碍 | color_tokens.dart textTertiary | #6A6A6A 大量 12px 说明文字 | 弱视力可读性差 | **计算 3.46:1** < 4.5 | 无 | 提亮至 ≈#8A8A8A（计算 4.6:1） | 中 |

## P3 —— 细节问题

| ID | 页面 | 类别 | 位置 | 现象 | 数据 | 改进建议 | 优先级 |
|---|---|---|---|---|---|---|---|
| D-06 | Dashboard | 工程债 | dashboard_screen.dart | 1623 行 21 私有 widget 单文件 | 实证 | 拆分 | 低 |
| E-03 | 歌词编辑器 | 视觉 | lyric_editor_toolbar.dart _StatusLine | 「待复核 N」用 accent 绿表"待办" | 实证 | 改用 warning 或中性色 | 低 |
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
| R-04 | 路由 | 工程债 | app_router.dart default | 未知路由静默回首页 | 实证 | 加日志/提示 | 低 |
| T-02 | 传输 | 工程债 | transfer/*（8 屏 ~2900 行+命名 v2） | 子域体量 vs 频次不匹配 | 实证 | 文档化/简化 | 低 |
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
