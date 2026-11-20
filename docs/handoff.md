# Handoff

## 目标

审计路线的第十八轮（第十七轮 PR #489 已合并为 `1e72d01`）。按第 17 轮交接的下一步第 1 项处理 I-03：把首次识别准备对话框 `asr_runtime_setup_dialog.dart`（957 行）照设置页的做法拆开。这是审计总表和页面报告表里最后一条未处理的条目。本轮要求有效代码量不少于 1000 行，PR 过 CI 后直接合并。

1. I-03（D-039）：
   - `asr_runtime_setup_controller.dart`：`AsrRuntimeSetupController`（`ChangeNotifier`）管状态和全部流程，包括检测、空间检查、安装、暂停继续、失败重试、识别已有模型、更换存储位置和应用高级设置。
     - 每次 await 后检查 `isDisposed`。
     - 忙碌判断有名字，按钮由 `actionsFor` / `isEnabled` 决定。
     - 两段重复的失败处理合成 `_installFailed`。
   - `asr_runtime_setup_cards.dart`：标题、编号步骤、模式菜单、方案卡、组件卡和组件行、提示、每个按钮，都是公开的无状态组件。
   - `asr_runtime_setup_text.dart`：`AsrSetupText`，对话框的全部句子。
   - `asr_runtime_setup_dialog.dart` 降到 248 行，只留选文件夹、路径对话框、高级设置对话框、提示条和关闭。公开入口 `AsrRuntimeSetupDialog(dependencies:)` 不变。
2. 读屏：标题和步骤是标题节点，步骤读成「第 N 步」，组件行读成一句（名称，状态，说明）。
3. 质量模式菜单改为撑满宽度，选项过长时用省略号。手机宽度下原来会溢出 57 px，新的 390 宽对话框测试发现了这个问题。其余布局和文案没变。
4. 审计表状态一节改为“第 18 轮核对”，I-03 标为已处理。两张表已经没有未处理的行。

## Git 现场

- 分支：`arena/a5080b84-lyric-forge-ktv`，基于 main `1e72d01`。
- PR #490（squash 合并）。
- 提交：`Split the speech recognition setup dialog into controller, cards and text`、`Add a temporary probe`、`Apply format, expand the mode menu and tidy the dialog tests`、`Remove the probe`。

## 已改文件

见工作日志 `2026-12-05-0930`、新决定 D-039，以及审计表状态一节。

## 检查结果

沙箱里没有 Dart/Flutter，所以格式、analyze 和测试都在 PR #490 的 CI 上跑，另外用一个临时探针工作流（合并前已删除）。探针结果：
- 第一次：
  - 新的手机宽度对话框测试发现质量模式菜单溢出 57 px，已修。
  - 有一条未用参数警告，三处已弃用的 `containsSemantics`，都改掉了。
  - 9 个 Dart 文件和 3 个 work log 文件有格式和生成差异，补丁已应用。
- 第二次：
  - analyze 没有错误和警告，181 条提示，和上轮相同。
  - 测试全部 3784 个通过、2 个跳过，比上轮多 86 个。改动的测试和 `test/architecture` 共 176 个用例全过。
  - 格式没有差异。

- 三个源码契约测试改为一起读对话框、卡片、控制器和文案四个文件，原有的字面量和“先保存，再应用，再重新检测”的顺序都保留。
- 导入方仍只导入 `asr_runtime_setup_dialog.dart`，展示层导入基线不变。

## 下一步

- 审计表已全部处理或撤销。之后的工作建议转向在真机上验证（第 14–18 轮都没做）：
  - 第 17 轮的网格和卡片；
  - 本轮的准备对话框在手机宽度和大字号下的表现；
  - 用 TalkBack / VoiceOver 听一遍卡片、编辑器行和准备对话框的步骤。
- 可选的拆分，目前没有维护上的问题：
  - `ai_transcription_settings_cards.dart` 约 565 行。有四个契约测试读这个路径，导入基线也不能增加。
  - `lyric_list_pane.dart` 约 1424 行。
- 手机端歌曲行和本地歌曲列表可以抽一个共享的歌曲行。
- 设置页和准备对话框现在各有一个控制器，有些流程是相似的（识别已有模型、空间检查）。如果以后要合并，共用部分应放进转写功能的 domain 层或一个不依赖 Flutter 的类。两个控制器互相导入会产生新的跨功能依赖边。

## 已知风险

- 没有在运行中的应用里看过。拆分保留了原来的布局、文案和流程顺序，但步骤和组件行的读屏标签是新的。
- “识别已有模型”的按钮只在检测、安装或识别中变灰，和以前一样。运行时是否在别处下载要到点按时才检查，因为对话框监听不到这个状态。
- 对话框关闭后，正在进行的检测或识别会继续跑完，但不会再通知界面。这和以前的 `mounted` 检查效果相同。

最后更新：2026-12-05 09:30（Asia/Taipei）
