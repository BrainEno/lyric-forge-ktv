# Work Log

> Active window: latest 5 entries. Older entries are preserved in `docs/work_log_archive.md`.
> Start with `docs/work_log_index.md`; read this file for recent implementation details.

### [2026-10-19 15:30] 区分 ASR 环境准备与文件下载进度

- Scope: 首次准备和识别设置共用的进度卡现在分别标注整体环境准备估算进度与当前文件下载百分比，避免把分阶段的准备百分比误认为模型下载百分比；保留文件大小、速度、剩余时间和断点恢复提示。
- Files: `lib/features/transcription/presentation/widgets/asr_install_progress_card.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/transcription/presentation/widgets/asr_install_progress_card.dart test/features/transcription/asr_install_experience_contract_test.dart` => No issues found
  - `flutter test test/features/transcription/asr_install_experience_contract_test.dart` => All tests passed
  - `git diff --check` => success
- Notes: 本阶段只改善进度表达，没有修改下载网络路由。用户已确认下一阶段采用系统代理优先、支持识别设置中手动指定的下载代理；不会默认使用未经验证的第三方镜像。
- Commit: `Clarify ASR setup and download progress`

### [2026-10-19 15:44] 为 ASR 模型下载接入代理与连通性检查

- Scope: ASR 下载统一使用代理客户端工厂，依次检查手动 HTTP 代理、环境代理、Windows/macOS 静态系统代理并在无配置时直连；增加 Hugging Face 模型源测试按钮，将代理随识别配置保存，并为请求、响应体和下载流设置超时。进度 UI 仍分别呈现整体环境准备与单文件下载状态。
- Files: `lib/features/transcription/data/services/asr_download_http_client_factory.dart`, `lib/features/transcription/data/services/asr_download_connection_checker.dart`, `lib/features/transcription/domain/services/asr_download_connection_checker.dart`, `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`, `lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart`, `lib/features/transcription/data/services/resilient_asr_runtime_manager.dart`, `lib/features/transcription/domain/models/transcription_models.dart`, `lib/features/transcription/presentation/widgets/transcription_config_dialog.dart`, `lib/core/services/service_locator.dart`, `test/features/transcription/asr_download_http_client_factory_test.dart`, `test/transcription_config_test.dart`, `test/features/transcription/asr_runtime_resume_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - ASR 代理、配置、续传、进度、模型完整性及重试定向测试（6 个测试文件）=> All tests passed
  - `flutter analyze --no-fatal-infos`（本次变更涉及文件）=> success；13 条 info，无错误/警告
  - `dart format --output=none --set-exit-if-changed`（代理工厂、连通性实现及配置/代理测试）=> success
  - `git diff --check` => success
  - `flutter analyze --no-fatal-infos`（全项目）=> 被既有错误阻断：`fullscreen_ktv_interaction_surface_test.dart` 调用了不存在的 `WidgetTester.doubleTap`
- Notes: 代理仅支持无认证 HTTP 地址；不支持 SOCKS 与 PAC/WPAD 自动配置，检测到可识别的 PAC 设置时会提示手动填写。Linux 目前读取代理环境变量，不解析桌面系统代理。未使用第三方镜像；尚未对真实 Hugging Face 网络及系统代理进行端到端下载验证。
- Commit: `Add proxy support for ASR downloads`

### [2026-10-19 15:55] 立即持久化安装流程中的高级识别设置

- Scope: 在首次环境准备/批量导入的安装弹窗中，用户从高级设置确认代理或其他识别配置后立即保存到共享本地设置存储，不再等到外层弹窗完成；持久化失败时在弹窗内明确提示，避免用户重试时误以为配置已保存。
- Files: `lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `docs/work_log.md`
- Validation:
  - `flutter test test/features/transcription/asr_install_experience_contract_test.dart test/features/settings/transcription_settings_contract_test.dart test/transcription_config_test.dart` => All tests passed
  - `flutter analyze --no-fatal-infos lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart test/features/transcription/asr_install_experience_contract_test.dart` => No issues found
  - `git diff --check` => success
- Notes: 配置在高级设置对话框确认后先写入持久化存储，再应用到当前安装流程；下载中断后的重试和之后重新打开环境准备都会读取该代理。未改变取消高级设置时的行为。
- Commit: `Persist ASR advanced settings immediately`

### [2026-10-19 16:11] 允许代理独立保存并在对话框内提示缺项

- Scope: 将下载代理持久化拆成独立操作；高级设置中的识别模型/路径不完整时仍可保存代理并退出，重新打开时恢复代理。缺少的识别项在高级设置窗口内实时提示，不再用主界面提示或配置完整性校验阻断代理保存。
- Files: `lib/features/transcription/domain/services/transcription_settings_store.dart`, `lib/features/transcription/data/services/file_transcription_settings_store.dart`, `lib/core/services/service_locator.dart`, `lib/features/transcription/presentation/widgets/transcription_config_dialog.dart`, `lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart`, `lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart`, `test/features/transcription/file_transcription_settings_store_test.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - 设置存储、代理保存、配置合同、环境预检及队列恢复定向测试（6 个测试文件）=> All tests passed
  - `flutter analyze --no-fatal-infos`（本次涉及的 8 个 Dart 文件）=> success；6 条既存 info，无错误/警告
  - `dart format --output=none --set-exit-if-changed`（本次涉及的 Dart 文件）=> success
  - `git diff --check` => success
- Notes: 代理写入现有 transcription settings JSON 的独立字段；部分配置不会被常规 `load()` 当作可运行识别配置返回，因此不影响环境预检或实际转录。成功保存完整配置时仍沿用原有完整配置保存流程。
- Commit: `Allow saving ASR proxy independently`

### [2026-10-19 16:48] 修复识别歌词未关联到本地歌曲

- Scope: 本地识别完成后，将歌词工程 ID 持久化关联到原音频的本地媒体元数据，并刷新播放队列中对应歌曲的 `hasLyrics` 状态，使当前播放和后续打开歌曲时都能解析、显示识别歌词；歌词文件导入复用相同关联逻辑。
- Files: `lib/features/player/domain/services/playback_lyrics_project_linker.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`, `lib/features/player/presentation/widgets/local_song_lyrics_import_action.dart`, `lib/core/services/service_locator.dart`, `test/features/player/playback_lyrics_project_linker_test.dart`, `docs/work_log.md`
- Validation:
  - `flutter test test\features\player\playback_lyrics_project_linker_test.dart test\features\player\now_playing_lyrics_project_action_test.dart` => All tests passed
  - `flutter analyze --no-fatal-infos`（本次修改的 5 个 Dart 文件）=> success；11 条既有 info，无错误/警告
  - `dart format --output=none --set-exit-if-changed`（新增服务及测试）=> success
  - `git diff --check` => success
- Notes: AXTree 报错未证明是歌词无法显示的原因；本次修复了识别工程与本地歌曲之间缺失的 `linkedProjectId` 关联。未运行全量测试或 GUI 手动验证。
- Commit: `Link transcribed lyrics to local songs`
