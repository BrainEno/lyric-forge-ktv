# Handoff

## 目标

审计路线的第八轮（第七轮 PR #479 已合并为 `2de2786`）。每轮多做几个任务，lib+test 代码量至少 800 行：

1. A-01 强调色：用户同意更换，要求和错误色分开、好看。改为淡紫 Elysium Lavender `#B69CFF`（悬停 `#C7B3FF`、按下 `#9F84F0`、16% 底色 `accentMuted`），按钮文字仍为黑色（9.2:1）。绿色 `#1DB954` 只表示“完成”（工程“就绪”状态点、参考歌词对比里的新增文字、制作进度的已完成步骤），红色只给品牌标记和错误。决定见 D-031。
2. 工程播放器传输区合并：`ProjectPlayerTransport` 用一份状态、一组动作和三种布局（侧栏 / 顶部 / 矮窗口单行）取代 `_TransportPane`、`_CompactTransportHeader` 和 `_PlaybackControls` 包装；`player_screen.dart` 从 1404 行减到约 950 行。
3. SE-04 拆分 `AiTranscriptionSettingsSection`：四张卡片（方案、模型与存储、安装与维护、高级设置）改为无状态组件，文案放进纯函数 `AsrSettingsText`；页面状态和安装、迁移、删除流程留在原组件（约 600 行）。“查看当前路径”改为一行一个路径；新测试发现展开项的水波纹被卡片背景挡住，已修好。
4. P-03 工程详情宽屏：双栏不再按窗口宽度判断，而是按内容区实际宽度（≥880 px）判断，侧栏约占三分之一（320–440 px）。
5. 制作进度配色：已完成的步骤用绿色，当前步骤用淡紫色圆环，后面的步骤用灰色。

## Git 现场

- 分支：`arena/c07438ee-lyric-forge-ktv`，基于 main `2de2786`。
- 提交：`Switch the accent to Elysium Lavender`、`Give the project player one transport`、`Split the AI transcription settings into cards`、`Pick project detail columns from the content width`、`Colour finished production steps green`、`Remove the format probe and update the handoff`。

## 已改文件

见工作日志 `2026-11-26-0900` 至 `2026-11-26-1010` 的五条记录。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑。本轮用了一个临时探针工作流（合并前已删除），把格式差异、analyze 结果、测试失败和异常的上下文写进注解。靠它修掉了：漏掉的品牌色常量，几处格式问题，封面收敛契约测试里的旧路径，一个浮点比较，以及高级设置卡片的 ListTile 水波纹断言。行长度在本地按字符数检查过；工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- 剩余审计项：沉浸式 KTV 控件，T-02/T-03（传输子域体量），B-02 的文档残留（例如迁移弹窗里的 “LyricForge ASRRuntime” 是不是真实的目录名，需要确认）。
- 需要在运行中的应用里看一下淡紫强调色：KTV 已唱部分、滑块、主按钮、选中的筛选标签。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- 强调色改了以后，所有用 `AppColors.accent` 的地方（42 个文件，约 105 处）都会一起变色。其中用强调色表示“完成”的地方已经找出来改成绿色了，但仍可能有漏掉的。
- 工程详情的双栏阈值（880 px）是按代码推算的，没有截图核对。

最后更新：2026-11-26 10:20（Asia/Taipei）
