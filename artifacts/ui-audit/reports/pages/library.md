# 页面审计：音乐库（`/library` 五分区 shell）

> 证据类型：静态代码审查。截图：无。

## 页面用途
本地曲库：歌曲 / 艺人 / 专辑 / 收藏 / 歌单 五分区，共用 `LocalMusicLibraryShell`（顶部 ChoiceChip 条 + IndexedStack 保活）。
文件：local_music_library_shell.dart (256)、local_library_explorer_screen.dart (1130)、local_artist_album_browser_screen.dart (970)、local_collections_screen.dart (1297)。

## 主要组件
- `_SectionStrip`：5 个 ChoiceChip（图标+文字）+ 宽屏右侧「跨设备传输」IconButton；窄屏改用 `FloatingActionButton.small`。
- 歌曲区 `LocalLibraryExplorerScreen`：搜索、排序、列表；空态 `_EmptyLibrary`、无结果 `_NoResults`。
- 艺人/专辑区：网格 `_CatalogArtwork`；收藏/歌单：`_CollectionArtwork` + `local_collection_actions.dart`。

## 发现的问题
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| L-01 | 窄屏传输入口用 `FloatingActionButton.small`（Material 规格 40×40dp），**低于项目自定 48dp 触达规范**（AGENTS.md 明示）；且 FAB 会遮挡列表右下角内容 | local_music_library_shell.dart:143 | P2 |
| L-02 | 传输入口在两处：strip 右侧按钮（宽屏）与 FAB（窄屏）+ Dashboard 头部 + 全局播放条菜单 —— 全应用 4 处传输入口，优先级与频次不匹配 | shell/dashboard/global_player_bar | P2 |
| L-03 | ChoiceChip 分区条无选中态下划线/强指示，选中仅靠 Material chip 填充色（bgHighlight），5 个 chip 视觉权重相同 | _SectionStrip | P3 |
| L-04 | 三个分区各自实现 Artwork（_Artwork/_CatalogArtwork/_CollectionArtwork），占位样式无法统一 | 见 components.md §1.1 | P2 |
| L-05 | 搜索框样式硬编码 fontSize:11 | local_library_explorer_screen.dart:939 | P3 |

## 响应式（静态推断）
- shell 在 compact/medium 用 Scaffold+FAB，expanded+ 用裸 ColoredBox（外层已供 Scaffold）——结构合理。
- IndexedStack 保活五个分区，切换不丢滚动位置（代码注释明示），良好。

## 改进建议
1. FAB.small → 标准 48dp 触达或并入 strip 溢出。
2. 统一 `AppArtwork` 组件（含占位渐变/图标/圆角/错误回退）。
3. 评估传输入口收敛为全局 1 处（设置或库页）。
