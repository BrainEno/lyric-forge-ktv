# [2026-10-20 00:16] 新增参考歌词对齐服务

- Scope: 为"参考歌词纠正 ASR 草稿"做纯算法底座。用户粘贴/导入的参考歌词可能与 ASR 草稿存在错字、漏行、多余行，本轮在 domain 层完成行级序列对齐：归一化文本、计算字符级相似度、把参考行映射到 ASR 时间戳，并输出参考行视角与 ASR 行视角的双向状态，供后续逐行确认 UI 直接消费；本轮不改编辑器、不写工程文件。
- Files: `lib/features/lyrics/domain/models/reference_lyric_line.dart`（新增参考行模型，按行支持可选起止时间）、`lib/features/lyrics/domain/services/lyric_alignment_service.dart`（新增 Needleman-Wunsch 行级对齐、归一化、Levenshtein 相似度、时间映射与状态）、`test/features/lyrics/domain/services/lyric_alignment_service_test.dart`（13 个用例）、`docs/lyric_review_alignment_plan.md`（阶段 C1 标记完成）。
- Validation: `dart format`（模型、服务、测试）；`flutter analyze lib/features/lyrics/ test/features/lyrics/` 仅 4 条既有 info，无 error/warning；`flutter test test/features/lyrics/` 19/19 通过（含新增 13 个对齐用例与既有插入规则测试）；`dart tool/work_log.dart check` 通过。
- Notes: 相似度低于 `minimumPairSimilarity`（默认 0.5）不配对，避免把无关行硬配对；漏行只标记 `missing`、多余行只标记 `unmatched`，均不自动插入或删除。带时间戳的参考行直接采用自身时间，未带时间戳的行沿用 ASR 行时间；部分行带时间也按行判断。空行/纯标点行不参与对齐。当前按"行"对齐，ASR 与参考歌词断句不一致（一行拆成两行或两行合并）会表现为漏行 + 多余行，逐行确认 UI 中可手动处理；跨行重新切分不在本轮范围。
- Commit: `Add reference lyric alignment service`
