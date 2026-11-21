# [2026-12-18 09:30] Simplify the proofreading menu

- Scope: round 31. The user asked to continue the 歌词校对 work: optimise the remaining proofreading UI, remove the marginal (鸡肋) features and improve the ones that were incomplete, before looking at untimed web lyrics. Round 30's review had found that 一键校对 already performs the text clean-up, loop, repetition and timeline steps, yet each still had its own top-level entry; 参考歌词：只改文字 did what 参考歌词：纠正文字和时间轴 does when its timing box stays unticked, through a second dialog chain and a JSON timing-evidence import nobody could produce; 统一简繁字形 was a manual step recognition already performs; and the menu (23 entries) and the smart-proofreading dialog used engine jargon. Changes (D-053):
  - Removed the text-only reference flow: `RunReferenceProofreadUseCase`, `AsrReferenceCorrectionSuggester`, `ReferenceProofreadChangeSet`, `ReferenceProofreadReviewBuilder`, `TimingEvidenceJsonParser`, their three dialogs, `ReferenceLyricPurpose.textOnly`, the coordinator and screen entry points and their tests.
  - Folded 统一简繁字形 into 一键校对: `OneClickProofreadUseCase` unifies the minority-script rows after the clean-up (`ChineseScriptUnificationService`, the preference recognition recorded, else automatic; manual edits skipped) and reports `scriptFixes`; the manual dialog and its menu entry are gone.
  - Menu: 智能纠错 (一键校对, 智能校对, 粘贴参考歌词校对, re-recognition) → 文本整理 (查找替换, 整理断行) → 时间轴与打轴 (打轴, 逐字打轴, 平移) → one collapsed 单项检查 submenu (the four steps 一键校对 runs plus 漏唱和声, 语速, 逐字时间) → 对比与回滚. At most 15 top-level rows instead of 23; plainer subtitles.
  - Summary card: when 一键校对 is available, the hints it fixes collapse into one 一键校对修复 chip; the remaining hints stay as separate checks (还可检查).
  - Smart-proofreading dialog: ASR 优先 → 识别结果优先, ForcedAligner title → 用本机对齐模型核对逐字时间, plainer second-transcript texts.
- Files:
  - Deleted: `lib/features/lyrics/domain/proofreading/{asr_reference_correction_suggester,reference_proofread_change_set,reference_proofread_review_builder,run_reference_proofread_use_case,timing_evidence_json_parser}.dart`, `lib/features/lyrics/presentation/widgets/{reference_proofread_review_dialog,reference_proofread_timing_review_dialog,timing_evidence_import_dialog,chinese_script_unification_dialog}.dart` and their tests.
  - `lib/features/lyrics/domain/proofreading/one_click_proofread_use_case.dart`, `presentation/controllers/lyric_editor_proofreading_coordinator.dart`, `presentation/screens/lyric_editor_screen.dart`, `presentation/widgets/{lyric_proofread_menu_button,lyric_editor_actions,lyric_editor_content,lyric_recognition_summary_card,reference_alignment_dialog,auto_proofread_dialogs,lyric_proofread_dialog}.dart`, `presentation/lyric_review_strings.dart`, the subtitles of nine batch-tool dialogs.
  - Tests: one-click script cases, menu submenu cases, summary-card one-click chip, updated menu/actions/toolbar/save-conflict/orchestration-contract/dialog tests.
  - `docs/decisions.md` (D-053), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - The orchestration contract now checks `_runAutoProofread` instead of the removed `_openReferenceProofread`.
  - Untimed web lyrics shown as static, manually scrolled text in the player are a later feature (see handoff).
- Commit: `Simplify the proofreading menu`
