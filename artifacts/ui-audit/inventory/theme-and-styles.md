# 主题与样式审计（D. 交付物）

> 证据类型：**静态代码审计 + WCAG 公式计算**（对比度为按 W3C 相对亮度公式的计算值，标注为计算值；控件尺寸为代码中的 token 值，非运行实测）。

## 1. 主题系统构成

| 层 | 文件 | 内容 |
|---|---|---|
| ThemeData | `lib/core/theme/app_theme.dart` (297 行） | **仅 darkTheme**，无 lightTheme；`MaterialApp(theme: AppTheme.darkTheme)` 未设 `darkTheme`/`themeMode`，强制深色 |
| 颜色 token | `lib/core/theme/color_tokens.dart` (62 行） | `AppColors`：4 级背景/4 级文字/强调色/4 语义色/3 交互态/2 边框/2 渐变 |
| 间距 token | `lib/core/theme/spacing_tokens.dart` (49 行） | `AppSpacing`：4px 网格、8 级间距、5 级圆角、组件尺寸 |
| 响应式 | `lib/core/layout/app_responsive.dart` (222 行） | 宽度 5 档、高度 3 档、gutter/栏宽/最大内容宽 |
| 设计文档 | `docs/responsive-layout.md` | 断点标准（与代码一致） |

主题在 ThemeData 中覆盖：AppBar、Card、ElevatedButton、TextButton、IconButton、Input、ListTile、BottomNav、Slider、Progress、Divider、Tooltip、SnackBar、Dialog、Scrollbar、TextTheme（15 级）。**覆盖较全面。**

## 2. 主题系统是否承担全局职责？——基本合格，细节有缺口

token 使用广度（grep 实测）：

| token | 使用处数 |
|---|---|
| `AppColors.*` | 922 |
| `AppSpacing.*` | 1259 |
| `Theme.of(context)` | 297 |

**硬编码违规实测（全 lib/，已剔除 core/theme）：**

| 类别 | 数量 | 文件数 | 具体位置 |
|---|---|---|---|
| `Color(0x…)` 字面量 | **1** | 1 | seekable_progress_bar.dart:331（`Color(0x66000000)` 遮罩） |
| `Colors.*` Material 调色板 | 13 | 11 | 多为 `Colors.transparent`（合理）；**例外**：lyric_proofread_v2_dialog.dart:692,802,803 用 `Colors.amber.shade400/green.shade400` 作评级色——绕过语义色 token |
| `fontSize: <数字>` | 7 | 5 | lyric_editor_atoms:41(10)、lyric_list_pane:674(10)、reference_alignment_review:864/875/886(12)、local_artist_album_browser:849(12)、local_library_explorer:939(11) |
| `BorderRadius.circular(<数字>)` | 13 | 9 | 6/8/12/16 混用；token 已有 4/8/12/16 等价物未用 |
| `EdgeInsets` 数字字面量 | 2 | 1 | lyric_proofread_v2_dialog:686,810 |
| `fontWeight:` 直接指定 | 132 | 多 | 属 `copyWith(fontWeight:)` 语境化用法，合理 |
| `withAlpha/withOpacity` | 77 | 多 | 状态色派生，合理模式，但 alpha 值（16/18/20/26/82…）无统一阶梯 |

**结论：主题系统真正承担了全局职责，硬编码极少且集中。** 扣分项：①评级色绕过 token；②圆角字面量未走 token；③无 alpha 阶梯规范。

## 3. 色彩系统与品牌一致性

| token | 值 | 备注 |
|---|---|---|
| accent | `#1DB954` | **即 Spotify 绿**（color_tokens.dart:29 注释自承 "Spotify green as reference, adjusted"） |
| bgBase/bgElevated/bgSurface/bgHighlight | `#121212/#181818/#282828/#3E3E3E` | 与 Spotify 桌面端灰阶完全一致 |
| playerGradient | `#282828→#121212` | Spotify 式 hero 渐变 |

**应用图标**（assets/images/icon.png，本审计已直接查看）：红（≈#FF2A2A）+ 黑 + 米白三色、左侧红色唱片边条、粗块状 "F" 字标、右侧均衡器渐隐竖条、做旧印刷肌理。

**冲突判定（核心发现 B-01）**：图标的红/黑/米白体系与 UI 的 Spotify 绿/深灰体系**零交集**；UI 内除图标文件本身外没有任何红色品牌元素；导航 Rail 品牌位用原生 `Icons.graphic_eq_rounded`（app_navigation_shell.dart:108）。图标语言（红色音条、"F"、模拟质感）未延伸到 UI 任何位置。

## 4. 文字系统

| 项 | 实测 | 问题 |
|---|---|---|
| 字体族 | TextTheme 声明 `fontFamily: 'Inter'`（app_theme.dart:195） | **pubspec.yaml 未声明任何 fonts（fonts 段全为注释），资产目录无字体文件 → Inter 永不生效，静默回退系统字体；中文 UI 依赖系统 CJK 字体，无显式 fontFamilyFallback** |
| 字号阶梯 | 48/36/28/24/20/18/16/14/12/10 | 完整；标题 w700-w900，正文 w400 |
| 行高 | 1.1–1.5 按级设定 | 合理 |
| 歌词展示字号 | KTV 舞台当前行 headline 级 w900 纯白、邻行 textSecondary w600、未唱 textTertiary（fullscreen_ktv_lyric_stage.dart:48-96） | 层级清晰；无描边/阴影 Karaoke 增强（纯 Material 风） |

## 5. 间距/圆角/阴影/边框

- 间距：4px 网格 8 级 + section/content 语义值，执行度高（仅 2 处字面量违规）。
- 圆角：token 4/8/12/16/999；违规 13 处用了等价数字。
- 阴影：全局仅 2 处 BoxShadow（quick_play、seekable_progress_bar）——完全扁平；层级全靠 4 级背景色 + 1px borderSubtle/borderMuted。
- 边框：borderSubtle `#1AFFFFFF`、borderMuted `#0DFFFFFF`；卡片、面板、分隔统一，良好。

## 6. 控件状态与无障碍计算值

| 组合 | 对比度（计算值） | WCAG AA（4.5:1） | 判定 |
|---|---|---|---|
| textPrimary #FFF / bgBase | ≈18.4:1 | ✅ | |
| textSecondary #B3B3B3 / bgBase | ≈8.9:1 | ✅ | |
| **textTertiary #6A6A6A / bgBase** | **≈3.5:1** | ❌ | 大量 12px 说明文字使用（_mutedLabel 模式遍布各页） |
| accent #1DB954 / bgBase | ≈8.1:1 | ✅ | |
| **onPrimary #FFF / accent #1DB954**（ElevatedButton、SnackBar 文案） | **≈2.3:1** | ❌❌ | 主按钮白字绿底，AA/AAA 均不达标；SnackBar 同 |
| error #E22134 / bgBase | ≈4.6:1 | ✅（勉强） | |

其他无障碍实测：`Semantics()` 全项目仅 2 处；`minimumInteractiveExtent` 规范存在（48/40 分级）但 `FloatingActionButton.small`（local_music_library_shell，Material 规格 40dp）在触屏布局低于项目自定的 48dp 规范；键盘快捷键仅歌词编辑器有（Ctrl+S/Z/Y/H），播放器等核心页无快捷键。

## 7. 动画与过渡

页面转场统一 200ms FadeTransition（app_router._fadeRoute）；KTV 控制层 180ms AnimatedOpacity；其余依赖 Material 默认。无自定义品牌动效。

## 8. 汇总：设计规范偏离清单

| ID | 偏离 | 证据 | 级别 |
|---|---|---|---|
| S-01 | Inter 字体声明无效（未打包） | app_theme.dart:195 + pubspec.yaml | P1 |
| S-02 | 白字/绿底主按钮对比度 ≈2.3:1 | app_theme.dart elevatedButtonTheme + snackBarTheme | P1 |
| S-03 | textTertiary 对比度 ≈3.5:1 却承担大量说明文字 | color_tokens.dart + _mutedLabel 模式 | P2 |
| S-04 | 评级色用 Material amber/green 绕过 token | lyric_proofread_v2_dialog.dart:692,802-803 | P3 |
| S-05 | 13 处圆角字面量未走 token | 见 §2 表 | P3 |
| S-06 | 无 light 主题（产品定位桌面长时间使用，可接受但需决策记录） | app_theme.dart | P3 |
| S-07 | 无统一 alpha 状态阶梯 | 77 处 withAlpha 值分散 | P3 |
