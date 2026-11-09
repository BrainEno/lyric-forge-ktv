# Handoff

## 目标

在用户选择 KTV 音轨时捕获路径，避免关闭面板时被后续重建覆盖。

## Git 现场

- 基线 `eb9b179cd2d1ac42818d0d767dd916bd1ed17e25`；分支 `arena/1444c0b6-lyric-forge-ktv`。验证时快照：

```
M test/features/player/project_player_live_sources_test.dart
?? docs/log/entries/2026-11-07-1808-capture-ktv-source-choice.md
.../player/project_player_live_sources_test.dart   | 37 +++++++++++-----------
 1 file changed, 19 insertions(+), 18 deletions(-)
a0fa05d fix: capture KTV source path at selection
eb9b179 Merge pull request #390 from BrainEno/arena/16620829-lyric-forge-ktv
299fc84 docs: record live KTV entry validation
fddbf80 fix: retain selected source path during switching
d9d741a fix: keep KTV entry choices current
```

## 已改文件

- KTV 入口面板、工程播放器、两组 widget 测试和工作日志。

## 检查结果

- 固定 SDK Actions run 42615096091 通过定向测试、完整门禁及工作日志检查；本地无 Flutter/Dart。
- 未进行原生设备播放或手动 UI 检查。

## 下一步

- 设计并测试会话/音频操作协调：不可将整个 just_audio play Future 持锁，因为它可能等到播放结束。

## 已知风险

- 选择快照和前后复核不能串行化异步切换与切歌，也不能检测两次观察之间切走再切回；测试使用 fake。
- 自动分离、人声导入、旧副本清理未完成；Media Hub 上传 deadline 测试历史上间歇失败。

最后更新：2026-11-07 18:08（Asia/Taipei）
