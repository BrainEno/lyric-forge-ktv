# 页面审计：设置（`/settings`）

> 证据类型：静态代码审查。截图：无。

## 页面用途
识别运行环境管理 + 端到端冒烟测试 + 诊断。
文件：settings_screen.dart (87) + ai_transcription_settings_section.dart (**1008**) + asr_end_to_end_smoke_test_card.dart + diagnostics_settings_card.dart。

## 结构与问题
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| SE-01 | **内容与导航承诺不符**：导航 tooltip 承诺「播放、识别与存储设置」（app_destinations.dart:63），实际只有识别环境 + 冒烟测试 + 诊断三块；没有播放、存储、外观、快捷键等设置 | settings_screen.dart | P2 |
| SE-02 | **AppBar 标题「设置」与正文大标题「设置」重复**，双标题占首屏 | settings_screen.dart:24,43 | P3 |
| SE-03 | 副标题仍写「管理 **Elysium Player** 的本地运行环境」——旧品牌名 | settings_screen.dart:48 | P1（品牌） |
| SE-04 | AiTranscriptionSettingsSection 单组件 1008 行：模式选择、存储位置迁移（2 个确认弹窗）、模型下载/暂停/删除/重装、高级 ExpansionTile（手工路径/runtime/FFmpeg/设备/精度）全部内嵌——信息层级依赖用户自己展开理解 | ai_transcription_settings_section.dart:676-860 | P2 |
| SE-05 | 「冒烟测试」卡面向最终用户暴露端到端测试入口，属诊断工具，与"设置"心智不符（可并入诊断卡或高级区） | settings_screen.dart:69 | P3 |
| SE-06 | 设置页在 1920 宽屏：contentMaxWidth 1480 内单列长卡片，右侧大量留白（静态推断） | settings_screen.dart:33 | P3 |

## 改进建议
1. 设置分区化：识别 / 播放 / 存储 / 关于（诊断与冒烟测试并入关于或高级）。
2. 去掉正文重复大标题，保留副标题即可。
3. 品牌正名。
