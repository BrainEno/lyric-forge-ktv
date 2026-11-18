# 页面审计：工作台首页 Dashboard（`/` 与 `/dashboard`）

> 证据类型：静态代码审查。**截图：无（沙箱无 Flutter/GUI，见 environment-diagnostic.md）；多尺寸表现：基于 `AppResponsive` 代码的静态推断（已标注）。**

## 页面用途
应用根目的地「工程」：品牌头部 + 正在播放 Hero + 后台识别任务卡 + 最近播放横滑架 + 最近工程网格。
文件：`lib/features/home/presentation/screens/dashboard_screen.dart`（1623 行，单文件 21 个私有 widget）。

## 主要组件
_Header（标题+4 操作）→ _NowPlayingArea（_IdleHero/_PlayingHero + _PlaybackQueueCard）→ _BackgroundWorkCard（条件出现）→ _SectionHeader×2 → _RecentShelf（横向 ListView，卡宽 146/160）→ _ProjectGrid（1–4 列，minTileWidth 280）。

## 信息层级
- 主操作识别良好：FilledButton「导入并识别」是唯一填充按钮；「打开音乐」次级 Outlined。
- Hero 区无播放时显示营销文案（'把你的音乐库变成\n可以继续制作的 KTV 工程'）——空态 Hero 占 minHeight 190–250 + 装饰性封面方块，首屏信息密度低。
- 重复入口：「打开音乐」在 Header 出现 1 次、Hero 内 1 次、「最近播放」区 action 1 次 —— **同一目标 3 个入口**（问题 C-01）。

## 响应式表现（静态推断）
- ≥1080 且非矮屏：Hero 与队列卡双栏（2:1+sidePanel 340–420）。
- compact：Hero 单列；actions Wrap 换行；`_Header` 改纵排。未见溢出风险代码；`AlwaysScrollableScrollPhysics` + RefreshIndicator 保证可达。
- 1920 宽：contentMaxWidth 1480 封顶，居中，合理。

## 发现的问题
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| D-01 | 页头显示 `'Elysium Player'`、空工程文案亦用旧名——**产品改名未完成**，用户看到的品牌名与 LyricForge KTV / 应用图标完全无关 | dashboard_screen.dart:333,291；app.dart:67 `MaterialApp(title:'Elysium Player')` | P1 |
| D-02 | Hero/卡片渐变与绿色 accent 整体为 Spotify 视觉克隆，与应用图标（红/黑/米白）无联系 | dashboard _heroDecoration + color_tokens.dart | P1（品牌） |
| D-03 | 「打开音乐」入口 ×3，稀释主操作 | _Header/_IdleHero/_SectionHeader | P2 |
| D-04 | `_ListeningCard` 封面区永远显示渐变+音符图标（不读 history 封面路径？——`PlayHistory` 有 artworkPath 但卡片未使用，只用了 _Artwork 的默认分支） | dashboard_screen.dart:1382 `_Artwork(path: null…)` 调用处未传 path | P2 |
| D-05 | 窗口标题栏显示 "Elysium Player"（MaterialApp.title），任务栏/Alt-Tab 暴露旧品牌 | app.dart:67 | P1 |
| D-06 | 21 个私有 widget 挤在 1623 行单文件，维护性差（非视觉问题，记为工程债） | 全文 | P3 |

## 改进建议
1. 品牌正名：全局替换 Elysium Player → LyricForge KTV（title、页头、空态文案）。
2. Hero 区引入图标红色作为唯一强调（例如 _Eyebrow 或主按钮），建立图标↔UI 的锚点。
3. 「打开音乐」收敛为 1 个主入口。
4. _ListeningCard 改用真实封面路径。
