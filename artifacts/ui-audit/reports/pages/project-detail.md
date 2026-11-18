# 页面审计：工程详情（`/project/:id`）

> 证据类型：静态代码审查。截图：无。

## 页面用途
单个 KTV 工程的总览与下一步引导：状态、进度、歌词指标、元数据、操作面板。
文件：project_detail_screen.dart（1451 行）。

## 主要组件
SliverAppBar（工程名+返回）→ _ProjectHero（封面/状态药丸/阶段 pill/处理进度 _ProcessingProgress）→ _LyricStatusCard（_MetricChip×N）→ _ActionPanel「下一步」→ _ProjectMetadata（_MetadataRow 表）。

## 优点
- `_ActionPanel` 是本页设计最佳处：按工程状态条件渲染唯一主按钮（校对歌词 / 生成歌词 / 桌面提示），`_nextStepText` 一句话解释下一步；次级操作（打开播放器、重新识别、导入伴奏/人声、识别环境设置）按相关性垂直排列，视觉权重递减。
- 状态色语义清晰：ready=accent / error=error / 处理中=info / editing=warning（_StatusDot）。
- 处理进度、确认弹窗（重新识别/更换伴奏）完备。

## 发现的问题
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| P-01 | 状态指示体系碎：_StatusPill/_MiniPill/_StagePill/_MetricChip/_StatusDot 五种"pill"同页并存 | project_detail_screen.dart:695,723,878,1012 | P2 |
| P-02 | 「导入已有伴奏/更换伴奏」「导入已有人声/更换人声」两个低频操作与主操作同页平铺，技术术语（人声/伴奏 stem）需用户理解音频工程概念 | _ActionPanel | P2（可收进"高级"） |
| P-03 | 页面信息区（Hero/歌词卡/元数据/操作）在宽屏是否双栏需运行验证；静态看为单列 Sliver 长页，1280+ 可能留白过多 | _ProjectDetailContent | P3（静态推断） |

## 改进建议
1. 五种 pill 合并为 `AppBadge` 组件族（status/metric 两变体）。
2. 伴奏/人声导入收进二级「音频源管理」区。
