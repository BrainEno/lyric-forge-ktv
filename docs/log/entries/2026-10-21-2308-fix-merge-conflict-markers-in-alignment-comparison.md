# [2026-10-21 23:08] 修复参考对齐对比组件中的合并冲突标记

- Scope: `flutter analyze` 在 `lib/features/lyrics/presentation/widgets/reference_alignment_result_comparison.dart` 报出 9 个 error 与 3 个 warning。根因是该文件在 PR #126 合并（提交 228c258）时把未解决的 Git 冲突标记（`<<<<<<< HEAD` / `=======` / `>>>>>>> de9caeb`）一并提交进了 `main`，导致语法错误。清理冲突标记，保留 HEAD 侧语义（HEAD 与另一侧代码等价，仅缩进不同），并保持 `_LineChangeCard` 引用与 `_time`/`_diffService` 使用点不变。
- Files: `lib/features/lyrics/presentation/widgets/reference_alignment_result_comparison.dart`（删除 13 行冲突标记与重复分支）。
- Validation: `flutter analyze` → No issues found（33.6s → 3.3s）。`dart format lib/features/lyrics/presentation/widgets/reference_alignment_result_comparison.dart` → 0 changed。`flutter test test/features/lyrics` → 195/195 通过。
- Notes: 冲突标记此前已进入 `main` 历史（`git show HEAD:...` 可复现），本次只修工作区文件，未做提交或历史改写；提交方需自行决定如何处理该提交。`linux/ macos/ windows/` 下的 `generated_plugin*` 文件在工作区显示为已修改，但 `git diff --ignore-cr-at-eol` 为空，纯属 `core.autocrlf=true` 造成的行尾差异，未做改动。本次未做桌面/移动端真实窗口的人工验证。
- Commit: Resolve leftover merge conflict in reference alignment comparison
