# Handoff

## 目标

按全仓审计报告（main @3f6e7b7）的建议顺序，优先修复数据保护与 CI 问题，并处理 R-05 的语言统一：

- #438（R-01）：“保存并返回”必须等写盘成功才离开。失败、冲突，或保存期间又有新编辑时，保留编辑器和草稿。
- #439（R-02）：音乐库或收藏文件只读出一部分时，禁止用读到的子集覆盖原文件。
- #440（R-03）：首次加载失败不缓存，同一实例可以安全重试。
- #441（R-04）：修复 main 上 “total upload deadline” 测试失败（拒绝响应在连接 reset 后丢失）。
- #442（R-05）：校对提示统一为简体中文（部分完成，见“下一步”）。

#319 保持 OPEN，本轮未涉及。

## Git 现场

- 分支：`arena/eacfa9ab-lyric-forge-ktv`，基于 `3f6e7b7f139a30491d9a30b4a445fa55cec6fd1e`。
- 实现提交：`Protect lyric saves, local stores, and rejected uploads`。
- PR 状态和 head 以 GitHub 为准。
- 若分支上出现临时诊断 workflow `.github/workflows/followup-validation.yml`，合并前必须删除，不得进入 main。

## 已改文件

- **#438**
  - `lyric_editor_screen.dart`：`_saveChanges` 返回 `Future<bool>`，多次触发共用同一个进行中的保存。只有在写盘成功、且写盘期间没有新编辑时才返回 true。异常显示“保存失败…当前编辑仍保留”；冲突选“继续编辑”或“重新载入最新版”都不会离开。
  - `LyricEditorDocumentController.markSavedIfUnchanged`：只有编辑 revision 没变时才标记为已保存。
  - `lyric_editor_content.dart`：`onSave` 改为 `Future<bool> Function()`。新增 `isSaving`：保存中禁用保存按钮和 Ctrl+S，返回请求被忽略，按钮显示“正在保存…”。弹出前检查 `ModalRoute.isCurrent`，防止 pop 两次。
- **#439/#440**
  - 新增 `lib/core/persistence/retryable_load.dart`：多个并发调用共用一次加载，失败后不缓存。
  - 新增 `local_store_integrity.dart`（domain 层契约）和 `local_store_preservation.dart`：修复前先复制出 `.incomplete-<时间>.json` 副本，并逐字节校验。
  - 音乐库和收藏仓库：
    - 加载时先解析到局部变量，全部成功后才提交。
    - 整个文件无法读取时抛错，下次调用会重试。
    - 只有个别行无法读取时，可读行照常显示，所有写操作抛 `LocalStoreIncompleteException`；刷新只返回当前快照，不扫描也不写盘。
    - `repairKeepingReadableRecords` 只能由用户确认后调用。
  - metadata 仓库：改用 `RetryableLoad`，重试前清空旧状态。
  - 重新定位（relink）服务：第一次写入前检查两个仓库，任一不完整就直接拒绝。
  - 界面：
    - 音乐库页面新增 `LocalStoreIntegrityBanner`，提供“保留原文件并修复”和确认对话框。
    - 收藏页面和收藏按钮的报错改用 `describeLocalLibraryError` 给出中文说明。
    - 删除歌曲改走 `_withWork`，失败时显示错误。
- **#441** `http_media_hub_service.dart`：
  - 先释放上传资源（partial 文件、目标预留、上传槽位、计时器），再发送任何响应。
  - 拒绝时先发送并 flush 完整 JSON，再在 `incomingRejectionDrainGrace`（默认 1 秒，最多 16 MiB）内继续读并丢弃剩余请求体，然后关闭连接。
  - 如果超时发生时还有读取在进行，drain 接着这次读取，不在同一个 iterator 上再发起第二次。
- **#442**：
  - `LyricReviewStrings` 中两条 ForcedAligner 英文说明改为中文。
  - 试听期间音源变化时的错误改为中文。
  - 新增 `lyric_review_language_contract_test.dart`：扫描歌词展示层源码，禁止只有英文的提示句，允许模型和产品标识出现。
- **测试**：
  - 新增：`lyric_editor_save_and_return_test.dart`（8 项）、`local_store_integrity_test.dart`、`retryable_load_test.dart`、`local_store_integrity_banner_test.dart`、`lyric_review_language_contract_test.dart`。
  - 扩展：document controller 测试、relink 预检测试、上传测试（新增 3 项：拒绝响应完整送达、成功后槽位立即释放、drain grace 参数校验）。

## 检查结果

- 沙箱里没有 Flutter/Dart SDK。借鉴 #437 的做法，用分支上的临时 workflow 在固定版本 SDK 下验证，验证后已删除。
- Run `43595900121`：
  - `dart format` 改了 7 个文件，已经提交。
  - 新的保存并返回测试，以及 2 个原有的冲突对话框测试失败。原因有两个：保存中的无限转圈动画让 `pumpAndSettle` 在冲突对话框期间一直等不到结束；测试在重建之前就触发了返回。
  - 修复：保存状态改用静态图标；测试 helper 在返回前先 pump。
- Run `43596922207`（head `f8cd03b`）：
  - work-log check exit 0（仅剩 1 条原有的 commit-subject 警告）。
  - analyze 没有 error 或 warning。
  - 相关测试 215 项全部通过。
  - 上传测试文件连续跑 3 次，全部通过。
  - 完整 `flutter test`：2016 项通过，1 项跳过（仅 Windows）。
- 合并前以 PR 上的 Flutter Quality Gate 为准。

## 下一步

1. 确认 PR 的 Flutter Quality Gate 为绿。注意并行的 PR #443 也修改了 #438–#440 的同一批文件，但设计不同（遇到坏行直接失败，而不是只读加确认修复）。两者只能合并一个，或者合并前先 rebase 处理冲突。
2. #442 剩余工作：本轮只确定简体中文为唯一支持的界面语言，并以中文兜底。真正的语言切换和缺失 key 回退需要引入 `flutter_localizations` 并修改 lockfile，需要用户确认后再做。
3. 审计报告建议的后续顺序：ASR 基线（#413/#319）→ 发布与设备验证（#322/#223/#226/#415）→ UX（#416/#258/#231）。

## 已知风险

- 修复会在用户确认后丢弃无法读取的行。原文件副本会逐字节校验后保留，但不会自动清理。
- drain 只是让客户端有机会读到响应，客户端仍持续写入时不保证一定能读到。宽限期和字节上限都有限制，所以不能用来拖住服务器。
- 保存的冲突检查基于 revision，不是文件锁。
- 以上修改还没有在真机上验证。

最后更新：2026-11-14（Asia/Taipei）
