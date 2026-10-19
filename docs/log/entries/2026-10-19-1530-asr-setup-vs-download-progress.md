# [2026-10-19 15:30] 区分 ASR 环境准备与文件下载进度

- Scope: 首次准备和识别设置共用的进度卡现在分别标注整体环境准备估算进度与当前文件下载百分比，避免把分阶段的准备百分比误认为模型下载百分比；保留文件大小、速度、剩余时间和断点恢复提示。
- Files: `lib/features/transcription/presentation/widgets/asr_install_progress_card.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/transcription/presentation/widgets/asr_install_progress_card.dart test/features/transcription/asr_install_experience_contract_test.dart` => No issues found
  - `flutter test test/features/transcription/asr_install_experience_contract_test.dart` => All tests passed
  - `git diff --check` => success
- Notes: 本阶段只改善进度表达，没有修改下载网络路由。用户已确认下一阶段采用系统代理优先、支持识别设置中手动指定的下载代理；不会默认使用未经验证的第三方镜像。
- Commit: `Clarify ASR setup and download progress`
