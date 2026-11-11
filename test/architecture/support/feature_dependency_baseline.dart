// Existing cross-feature cycles and presentation imports at main cce30b8.
// Remove entries as boundaries are fixed; do not add new violations.
const cyclicEdgeBaseline = <String>{
  'lyrics -> player',
  'lyrics -> project',
  'player -> lyrics',
  'player -> project',
  'player -> transcription',
  'project -> player',
  'project -> transcription',
  'transcription -> lyrics',
  'transcription -> player',
  'transcription -> project',
};

const presentationImportBaseline = <String>{
  'lib/features/home/presentation/dashboard_dependencies.dart -> lib/features/transcription/presentation/transcription_screen_dependencies.dart',
  'lib/features/home/presentation/screens/dashboard_screen.dart -> lib/features/transcription/presentation/widgets/transcription_config_dialog.dart',
  'lib/features/import/presentation/screens/import_audio_screen.dart -> lib/features/transcription/presentation/widgets/transcription_queue_panel.dart',
  'lib/features/import/presentation/screens/transcription_ready_import_screen.dart -> lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
  'lib/features/import/presentation/transcription_import_dependencies.dart -> lib/features/transcription/presentation/transcription_screen_dependencies.dart',
  'lib/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart -> lib/features/player/presentation/widgets/seekable_progress_bar.dart',
  'lib/features/project/presentation/project_detail_dependencies.dart -> lib/features/transcription/presentation/transcription_screen_dependencies.dart',
  'lib/features/project/presentation/screens/project_detail_screen.dart -> lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
  'lib/features/settings/presentation/settings_screen_dependencies.dart -> lib/features/transcription/presentation/transcription_screen_dependencies.dart',
  'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart -> lib/features/transcription/presentation/transcription_screen_dependencies.dart',
  'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart -> lib/features/transcription/presentation/widgets/asr_existing_model_actions.dart',
  'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart -> lib/features/transcription/presentation/widgets/asr_install_error_card.dart',
  'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart -> lib/features/transcription/presentation/widgets/asr_install_progress_card.dart',
  'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart -> lib/features/transcription/presentation/widgets/asr_storage_preflight_card.dart',
  'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart -> lib/features/transcription/presentation/widgets/transcription_config_dialog.dart',
};
