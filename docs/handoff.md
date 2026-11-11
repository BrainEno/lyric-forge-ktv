# Handoff

## 目标

继续改进歌词识别质量和 #319 独立重识别安全接入。本阶段修复双引擎多对一分段时，次引擎长句可能自动替换多个主引擎行的问题；跨行候选只供人工复核，校对面板不提供单行一键采用。

## Git 现场

基线 `c6e6406e2b71674d52664aae3a52d6d8306c1ee0`，分支 `arena/fe82655d-lyric-forge-ktv`。记录前 `git status --short` 显示融合服务、校对面板和各自测试 4 个已修改文件，`git diff --stat` 为 4 files changed, 165 insertions(+), 76 deletions(-)（相对首个提交的格式调整）；`git log --oneline -5` 为 `50c4073 Protect shared secondary ASR segments`、`c6e6406 Merge pull request #410`。以当前 Git 状态为准，临时验证 workflow 不应进入 PR。

## 已改文件

`high_quality_transcription_service.dart`、`lyric_inspector_pane.dart`、相应双引擎与 widget 测试、交接及工作日志导航。

## 检查结果

本地无 Flutter/Dart。固定 SDK Actions 42943660214：格式、`test/high_quality_transcription_service_test.dart`、`test/resumable_chunked_transcription_service_test.dart`、`test/features/lyrics/presentation/widgets/lyric_inspector_pane_test.dart` 及 `flutter analyze --no-pub --no-fatal-infos lib test tool` 通过。工作日志和正式 PR 门禁另见后续 Actions；真实模型、歌曲和设备未验证。

## 下一步

统一接入设置、向导、自检的调用者独立安装包装器和 app-scoped 协调器，禁止绕过；先处理界面外层预检、busy 后独立 repair、自检取消时序，再增加并发及 widget 测试。

## 已知风险

对应行依赖时间与文本启发式，错误时间戳或分句仍可能误匹配、漏字或误报；本阶段仅保护被检测到的跨多条主稿的共享次引擎段，未修复所有融合风险。旧工程候选没有新标记，不受新界面限制。人工歌词不会在复核时静默改写，但基于模型置信度的一对一自动融合仍是草稿策略。真实歌曲人工标注基准缺失，无法声称 CER、召回或准确率提升；应按 `docs/asr_quality_baseline.md` 测量原模型和双引擎结果。

手工验证：用两种主引擎顺序构造短行对应同一长行的音频结果，检查主稿和时间不变、两行均显示备选和跨行提示、无一键采用，仍能人工编辑；普通单行备选仍可主动采用；检查紧凑/宽屏布局和重开工程后的提示。未在设备执行。

安装协调包装器未生产接线，自检仍可能取消其他入口的安装；独立 repair、迁移/导入/删除和跨进程资源未协调，独立重跑无生产调用者。

最后更新：2026-11-07（Asia/Taipei）
