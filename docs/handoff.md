# Handoff

## 目标

审计路线的下一轮（PR #474 已合并为 `4969c1c`）。这一轮多做几个任务：

1. K-01 KTV 舞台逐字着色：当前行按字/词随演唱变色，有逐字时间轴时按真实时间。
2. R-04 未知路由显示“页面不存在”（带路由名、回到首页、返回上一页），并记录警告日志。
3. `AppEmptyState` 新增 hero 密度（大图标卡片、标题、可滚动）和 status/footer 插槽；快速播放、歌曲库、艺人/专辑、收藏/歌单的空状态统一改用它。
4. L-01/L-03 音乐库窄屏去掉 40dp 小浮动按钮，传输按钮在所有宽度都放在分区条末尾（≥48dp）；全局 Chip 选中态加强调色描边和浅绿底。

## Git 现场

- 分支：`arena/08eecee8-lyric-forge-ktv`，基于 main `4969c1c`。
- 提交：`Add a karaoke wipe to the KTV stage`；`Fix the karaoke line test and format the KTV files`；`Show a page for unknown routes`；`Move library empty states to AppEmptyState`；`Restore the formatter's layout in two KTV files`；`Move the library transfer button into the section strip`。

## 已改文件

见工作日志 `2026-11-19-1115-add-karaoke-wipe-to-ktv-stage.md`（逐字着色组件、KTV 舞台、沉浸 KTV 页）和 `2026-11-19-1125-show-a-page-for-unknown-routes.md`（未找到页面、路由表）和 `2026-11-19-1135-move-library-empty-states-to-app-empty-state.md`（空状态组件和四个音乐库页面）和 `2026-11-19-1145-move-library-transfer-button-into-section-strip.md`（音乐库分区条、Chip 主题）。

## 检查结果

沙箱没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上运行。本地按字符数检查了行长度，用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。

## 下一步

- 本轮其余任务见 PR 描述。之后：全局/移动播放条紧凑控制、SE-05 冒烟测试卡片面向用户的文案、Forge Red 品牌色（B-01）。

## 已知风险

- 没有在运行中的应用里看过。KTV 舞台当前行会随演唱逐字变绿；没有在真机上看过实际播放时的流畅度。未知路由不再静默回到首页。详见工作日志。

最后更新：2026-11-19 11:45（Asia/Taipei）
