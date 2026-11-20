# Handoff

## 目标

审计路线的第十七轮（第十六轮 PR #488 已合并为 `51a16c1`）。总表各行在第 16 轮都已处理，这一轮核对只出现在页面报告里的十条，并处理其中仍然成立的 L-04（封面）和 T-03（手机端曲库不复用本地组件）。本轮要求有效代码量不少于 1000 行，PR 过 CI 后直接合并。

1. L-04 / T-03（D-038）：
   - 新共享组件 `core/widgets/app_catalog_card.dart`：本地的歌手 / 专辑、歌曲、播放列表网格和手机端的歌手 / 专辑网格都用它。
     - 一种圆角、两档内边距、正方形封面；底色是 `Material`，看得到水波。
     - 红边框只给打不开的条目。
     - 网格规则（`gridDelegateFor`）也在这里。
   - `AppArtwork` 加了 `tileRadius` / `rowRadius`、`AppArtwork.person`（圆形）、`AppArtwork.missing`（断链）和公开的 `AppArtworkPlaceholder`；三个私有封面包装删掉了。
2. 手机端封面 `RemoteMediaArtwork` 用 `AppArtwork` 的边框和占位，歌手是圆的；取图方式不变（固定证书通道，token 在请求头）。
3. 手机端歌曲行的下载状态只由新的 `remote_track_download.dart` 推出一次：图标、进度条、提示和读屏标签读的是同一个状态。已在手机上的歌曲不再同时显示 ✓ 和旧的“下载失败”。
4. 审计总表状态一节改为“第 17 轮核对”，补一张页面报告条目表：
   - 已处理：D-02、D-03、E-01、SE-04（随更早的改动）和 L-04、T-03（本轮）。
   - 撤销：D-01、D-05、SE-03。
   - 未处理：I-03。

## Git 现场

- 分支：`arena/88638761-lyric-forge-ktv`，基于 main `51a16c1`。
- 提交：`Share one catalog card and cover across the music libraries`，以及临时探针的添加、修正和删除。

## 已改文件

见工作日志 `2026-12-04-0930`；新决定 D-038；审计总表状态一节。

## 检查结果

沙箱里没有 Dart/Flutter。格式、analyze 和测试只在 PR 的 CI 上跑，另外用一个临时探针工作流（合并前删除）。工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`。CI 结果见 PR。

## 下一步

- I-03：识别环境安装弹窗 `asr_runtime_setup_dialog.dart` 仍有约 957 行，可以按设置页的做法拆成区块、卡片和流程。
- 手机端歌曲行仍是自己的行布局（有下载按钮和进度条）。如果以后本地歌曲列表也要统一，可以抽一个共享的歌曲行。
- 在真机上看一遍（第 14–17 轮都没做）：
  - 本轮的网格：播放列表改成正方形封面的两列以上网格；歌曲卡的内边距变大；手机端卡片的间距变大。
  - 大字号下卡片是否溢出。
  - 用 TalkBack / VoiceOver 听一遍卡片。
- `ai_transcription_settings_cards.dart` 约 565 行、`lyric_list_pane.dart` 约 1424 行，都可以再拆，但目前没有维护上的问题。

## 已知风险

- 都没有在运行中的应用里看过。网格比例是按文字高度估的（手机 0.74、其他 0.72）；字号放大很多时，封面会先缩小，但文字仍可能挤。
- 播放列表网格从固定 190–220 高、最少一列，改成和专辑一样的比例、最少两列；很窄的窗口里播放列表卡会比以前小。
- `AppCatalogCard` 用 `AppTapTarget` 排除了卡内语义（D-037）。卡里新加按钮时要同时加进 `semanticActions`。

最后更新：2026-12-04 10:40（Asia/Taipei）
