# 页面审计：歌词校对编辑器（`/project/:id/lyrics`）

> 证据类型：静态代码审查。截图：无。本页是应用功能密度最高的页面。

## 页面用途
逐行校对识别歌词：文本、起止时间、复核决策、批量工具、导出。
主文件：lyric_editor_screen.dart (1181) + lyric_editor_content.dart (822) + lyric_editor_toolbar.dart (550) + lyric_list_pane.dart (1358) + lyric_inspector_pane.dart (972)。

## 布局结构
- AppBar：标题「歌词校对」+ 工程名副标；actions = [窄屏时校对菜单 compact 图标] + [LyricEditorOverflowMenu ⋯] + [有改动时「保存修改」FilledButton]。
- LyricEditorToolbar：状态行（行数·语言·待复核数）→ Wrap 控件带（试听、筛选菜单、跟随播放、偏移菜单、[条件]循环单行、[宽屏]校对菜单）→ [试听中]SeekableProgressBar。
- 内容：≥1080 双栏（列表 | 340–420 检查器），窄屏列表 + 点行弹 88% 高 BottomSheet 检查器。
- 底部 _BottomBar：行计数 + 未保存徽标 + 添加歌词行。

## 已验证的良好实践（不应回退）
- 2026-10-31 的 UX 复盘（docs/lyric_proofreading_ux_review.md）已落地：行内双击编辑、时间戳直输弹窗、列表搜索（>8 行出现）、4 滤 chip 收敛为 1 个筛选菜单、20 个校对工具收敛为 1 个菜单。
- 离开保护 PopScope + 未保存对话框 + 保存冲突对话框；Ctrl/Cmd+S/Z/Y/H 快捷键。
- 空态 `_EmptyLyricsState` 双路径引导（去识别/手动建行）。

## 发现的问题
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| E-01 | **校对菜单 20 项单菜单过载**：仅 viewComparison 前 1 个 Divider 分组；每项标题+副标题双行，菜单高度可能超屏（静态推断：20 项×~48dp≈960dp，1080p 可容、800×600 矮屏必滚动且 MenuAnchor 默认滚动感差） | lyric_proofread_menu_button.dart | P2 |
| E-02 | 工具命名技术化：「智能校对 V2」（版本号外露）、「参考歌词纠正」vs「逐行智能纠错（保留时间戳）」差异需读副标题才懂 | 同文件 _textFor | P2 |
| E-03 | 筛选菜单项「待复核 N」直接以 accent 绿色显示在状态行，绿色在此承担"警告/待办"语义，与全局"绿=正常/品牌"语义冲突 | lyric_editor_toolbar.dart _StatusLine | P3 |
| E-04 | LyricEditorContent 构造函数 44 参数，toolbar 21 参数 —— 上帝参数对象，回调穿层深 | lyric_editor_content.dart:106 | P3（工程债） |
| E-05 | 行检查器窄屏为 88% 高 BottomSheet，遮上下文（复盘文档已知，标记为已缓解未根治） | lyric_editor_content.dart:212 | P3 |
| E-06 | `fontSize:10` 硬编码小字（行内徽标） | lyric_editor_atoms.dart:41、lyric_list_pane.dart:674 | P3（可读性） |

## 改进建议
1. 校对菜单按「生成提案 / 文本工具 / 时间轴工具 / 逐字工具 / 回滚」分 4–5 组并加分组标题；考虑把"打轴/逐字"两个高频 KTV 工具提为工具条一级按钮。
2. 「智能校对 V2」改名「智能校对」（版本号不进 UI）。
3. 引入 editor 状态对象减少参数穿层（工程任务）。
