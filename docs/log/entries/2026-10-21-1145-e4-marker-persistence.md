# [2026-10-21 11:45] 手工编辑保护标记跨会话持久化（E4.2）

- Scope: 阶段 E4 编辑器状态持久化主体。新增域层标记服务，把编辑器"手工改过的行"从会话级行索引改为基于稳定 lineId 的身份记录：插入、删除、参考对齐补行后保护不再随索引漂移；保存时写入文档 metadata，重开工程后自动恢复，避免重开后参考对齐静默覆盖用户改过的歌词。
- Files: 新增 `lib/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart`（assignMissingLineIds / persist / restore / prune / protectedIndices，metadata 键 `manuallyEditedLineIds`）；修改 `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`（会话状态改为 `Set<String>` 行标识 + 派生受保护索引 getter；加载时补齐行标识并恢复标记；保存时持久化标记；应用对齐后为新行补标识并删除索引重映射；插入/删除改为按标识增删；删除 `_shiftEditedIndices`；备份恢复时按标识取交集并合并备份内标记）；新增 `test/features/lyrics/domain/services/lyric_manual_edit_marker_service_test.dart`（11 例：标识分配、持久化/恢复/清理、插入删除后索引自动跟随、保存重开往返）。
- Validation: `dart format` 新服务与新测试文件（编辑器只格式化新增行，避免整文件重排）；`flutter analyze --no-pub` 两个变更文件 → No issues found；`flutter test --no-pub test/features/lyrics/domain/services/lyric_manual_edit_marker_service_test.dart` → 11/11 通过；`flutter test --no-pub` 全量 → 486 通过、2 跳过、0 失败。
- Notes: 编辑器页面依赖 ServiceLocatorGlobal 构建完整真实服务图（含音频插件），无法在普通 widget 测试中装配，因此状态逻辑下沉到可单测的域服务，页面只做编排；页面装配层仅有 analyzer 与代码审查覆盖，列为残余风险。旧版工程/备份没有行标识时，重开会分配新标识，旧标记自然失配（与旧行为一致，不会误保护）。时间轴微调不改变保护状态，只有文字改动才标记（与改动前语义一致）。多视口人工复核留待 E4.3 一并给出清单。
- Commit: Persist manual-edit markers by stable line identity
