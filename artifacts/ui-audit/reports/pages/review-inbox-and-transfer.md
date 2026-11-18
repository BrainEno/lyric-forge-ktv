# 页面审计：校对收件箱（`/review`）与传输域

> 证据类型：静态代码审查。截图：无。

## A. ReviewInboxScreen（350 行）
用途：列出所有含待复核行的工程，按待复核数排序，点入编辑器。
结构：AppBar「校对」+刷新 → 汇总行「N 个工程，共 M 行待复核」→ _ReviewInboxTile 列表（图标块+工程名+副标+_Badge 待复核/低置信度/未评分+箭头）。空态/错误态完备（_Message）。

问题：
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| R-01 | 列表项封面位置用固定歌词图标（44×44 灰块），不显示歌曲封面——与 Dashboard 工程卡（有封面）视觉不一致，也损失识别效率 | review_inbox_screen.dart:207-217 | P3 |
| R-02 | 已全复核的工程仍常驻列表（徽标「已复核」），无过滤/归档 | _ReviewInboxTile | P3 |
| R-03 | 无批量操作（如全部标为已复核），需逐工程进入 | — | P3 |

## B. 传输域（桌面 `/media-sharing` + 移动 `/remote-library` `/remote-library/browse` `/media-hub-scanner`）
文件：desktop_media_transfer_hub_v2_screen.dart (702)、mobile_media_transfer_hub_screen.dart、mobile_remote_library_shell.dart → 3 个子页（mobile_remote_music_library 803 行 / mobile_remote_grouped_library 521 / mobile_download_manager 536）、media_hub_qr_scanner_screen.dart。

结构（桌面 V2）：AppBar「电脑 ↔ 手机传输」→ _MediaHubSecurityNotice → _OverviewCard → _PairingCard（二维码 qr_flutter）→ _WaitingForPairingCard → _DirectionCard → _SharedTracksCard → _ErrorCard。状态机卡片式推进，加密确认弹窗（「开启加密的网络共享？」）。

问题：
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| T-01 | **死代码**：RemoteMediaLibraryScreen（632 行）零引用 | remote_media_library_screen.dart | P2 |
| T-02 | 传输相关屏达 8 个文件/2900+ 行，移动端壳含 3 子页；与四大目的地相比体量过重，但未进顶层导航（设计决策合理），发现性依赖库页/首页入口 | transfer/* | P3 |
| T-03 | 文件名带版本号（`..._v2_screen.dart`），暗示 V1 已删；远端浏览三子页与本地音乐库五分区在信息架构上部分同构但未复用组件 | mobile_remote_library_shell.dart | P3 |

## 改进建议
1. 删除或归档 RemoteMediaLibraryScreen。
2. 收件箱行项接 AppArtwork。
3. 传输域补一份 README 或合并子页文档，降低接手成本。
