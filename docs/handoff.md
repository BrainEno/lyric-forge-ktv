# Handoff

> 单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 `AGENTS.md` 与 `docs/work_log_index.md`。
> 只写"下一位执行者"真正需要的东西，不要粘贴日志正文或大段 diff。

## 目标

P1（统一各播放面的歌词可用性）已完成并提交：解析结果结构化、自愈后回撤/补写队列 `hasLyrics`、应用壳层随当前条目自动同步，歌词入口点击时同样走共享解析。工作日志条目化与新门禁（S1–S3）早已落地。

## Git 现场

```text
$ git status --short
(clean after this task's commit)

$ git log --oneline -4
44c8404 Unify playback lyrics availability across surfaces
22b651f Unblock analyzer and full test suite
976148a Add work log lint tool and quality gate hook
010bf9a Move work log entries to per-task files
```

## 已改文件

- 本片：`lib/features/player/domain/services/playback_lyrics_project_resolver.dart`（`PlaybackLyricsResolution` + 结构化解析 + 修复/清除标记）、`lib/features/player/domain/services/playback_lyrics_availability.dart`（新增，解析并回写队列标记）、`lib/features/player/presentation/widgets/playback_lyrics_availability_sync.dart`（新增，壳层同步器）、`lib/main.dart`（挂在 `MaterialApp.builder` 内、手机与桌面两个分支共用）、`now_playing_lyrics_project_action.dart`、`local_song_lyrics_import_action.dart`、两个测试文件、`docs/decisions.md`（D-005）。
- 更早：`tool/work_log.dart`、`test/work_log_tool_test.dart`、两套 quality gate 的文档校验、29 条历史条目文件。

## 检查结果

- `flutter analyze --no-pub --no-fatal-infos` => 0 error / 0 warning（149 条样式 info，未增长）
- `flutter test --no-pub --reporter expanded` => All tests passed（319 通过 / 2 跳过）
- `powershell -File scripts/quality_gate.ps1 -SkipPubGet` => Repository quality gate (all) passed
- `dart tool/work_log.dart check` => success

## 下一步

硬化解析器的破坏性自愈：`_projectFor` / `_scannedProjectIdForAudio` 现在把"读取异常"与"没有工程"都当作 null，`_healLink` 随后会清除 `linkedProjectId`。建议让扫描返回三态（命中 / 未命中 / 失败），失败时不写元数据、也不回撤队列标记（`PlaybackLyricsResolution` 增加权威性标记，`resolveAndSyncPlaybackLyrics` 据此跳过同步）。完成标准：`playback_lyrics_project_resolver_test.dart` / `playback_lyrics_availability_test.dart` 覆盖"仓库抛错时不清链接、不回撤标记"，全套测试保持全绿。

备选（产品向）：歌词关联冲突确认——在另一个工程里首次生成歌词会静默改写音频→工程链接，需要确认或提示。

## 已知风险

- 工程仓库读取异常仍会被当作"没有工程"，可能清除用户歌词链接（下一步要修）。
- 149 条样式 info 仍是技术债，`prefer_interpolation_to_compose_strings` 占 116 条，需按文件分片清理。
- 当前 SDK 的 `dart format` 会启用 tall style，对既有文件是整篇重排；不要对既有文件整体格式化，否则 diff 会被格式噪音淹没。
- 文档校验只在本地 quality gate 中执行，尚未接入 GitHub workflow。
- 归档导航 `docs/work_log_archive.md` 需手工补行：条目退出活动窗口时必须补，否则 lint 报 `entry-unreferenced`。
- 全屏 KTV 单击控件显示仍有约 300ms 的双击超时延迟（`onTap` 与 `onDoubleTap` 共存的标准代价）。

---

最后更新：2026-10-19 22:28
