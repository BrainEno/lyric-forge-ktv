# 页面审计：批量导入（`/import`）

> 证据类型：静态代码审查。截图：无。

## 页面用途
桌面核心漏斗：选择文件/文件夹 → 后台识别 → 生成工程。两阶段内嵌：识别环境未就绪时先显示 `_ReadinessOnboarding`，就绪后切换 `ImportAudioScreen`。
文件：transcription_ready_import_screen.dart (506) + import_audio_screen.dart (649)。

## 结构
- TranscriptionReadyImportScreen：AppBar「批量导入」；readiness 检查 → _ReadinessOnboarding（_ReadinessRow 列表 + 「准备识别环境」FilledButton + 「设置」OutlinedButton）。
- ImportAudioScreen：AppBar「批量导入」+ _ImportHero（_FeaturePill×N 卖点）+ _ImportActions（_ImportActionCard：选文件/选文件夹）+ _SelectionPanel（_SelectedPathTile 列表）。

## 发现的问题
| ID | 问题 | 证据 | 级别 |
|---|---|---|---|
| I-01 | 两个文件 AppBar 同名「批量导入」，但第一阶段实际内容是"识别环境准备"，用户预期管理导入任务却看到环境向导——标题与内容错配 | transcription_ready_import_screen.dart:165 / import_audio_screen.dart:110 | P2 |
| I-02 | _ImportHero 用 FeaturePill 罗列卖点，营销化信息占用核心漏斗页面首屏 | import_audio_screen.dart:188-306 | P3 |
| I-03 | 识别环境安装走 AsrRuntimeSetupDialog（981 行弹窗），安装失败/存储预检另有 3 个卡片组件（asr_install_error_card / asr_install_progress_card / asr_storage_preflight_card），错误路径组件多但层级清晰 | import + transcription/widgets | P3（观察） |

## 改进建议
1. 第一阶段标题改为「准备识别环境」。
2. Hero 卖点收敛为一行副标题。
