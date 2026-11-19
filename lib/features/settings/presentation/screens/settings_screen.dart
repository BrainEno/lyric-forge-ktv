import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../settings_screen_dependencies.dart';
import '../widgets/ai_transcription_settings_section.dart';
import '../widgets/asr_end_to_end_smoke_test_card.dart';
import '../widgets/diagnostics_settings_card.dart';
import '../widgets/library_folder_settings_card.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/settings_columns.dart';

/// The line under the app bar. It names only what the page holds; the
/// navigation tooltip used to promise playback and storage settings that do
/// not exist (audit SE-01).
const String settingsIntro = '曲库目录、本地 AI 识别环境，以及出问题时的诊断与试识别。';

class SettingsScreen extends StatelessWidget {
  final SettingsScreenDependencies dependencies;

  const SettingsScreen({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final libraryFolder = dependencies.libraryFolder;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: const Text('设置'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.pageGutter,
                AppSpacing.lg,
                layout.pageGutter,
                AppSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The app bar already says 设置; the page opens with what
                  // it manages instead of repeating the title (audit SE-02).
                  Text(
                    settingsIntro,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SettingsColumns(
                    primary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (libraryFolder != null) ...[
                          const SettingsGroupLabel(
                            key: ValueKey('settings-group:library'),
                            label: '音乐库',
                          ),
                          SettingsSectionCard(
                            icon: Icons.folder_special_outlined,
                            title: LibraryFolderSettingsText.title,
                            subtitle: LibraryFolderSettingsText.subtitle,
                            child: LibraryFolderSettingsCard(
                              settings: libraryFolder,
                              findLyrics: dependencies.findLibraryLyrics,
                              countAutoPaired:
                                  dependencies.countAutoPairedLyrics,
                              openAutoPaired: () => Navigator.pushNamed<void>(
                                context,
                                Routes.libraryAutoPaired,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        const SettingsGroupLabel(
                          key: ValueKey('settings-group:recognition'),
                          label: 'AI 识别',
                        ),
                        AiTranscriptionSettingsSection(
                          dependencies:
                              dependencies.asrRuntimeSetupDependencies,
                        ),
                      ],
                    ),
                    // Diagnostics first: exporting a report is what support
                    // asks for. The trial run used to sit between the
                    // recognition settings and diagnostics as if it were a
                    // setting (audit SE-05). On wide windows this group is
                    // the right-hand column (audit SE-06).
                    secondary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SettingsGroupLabel(
                          key: ValueKey('settings-group:troubleshooting'),
                          label: '故障排查',
                        ),
                        DiagnosticsSettingsCard(
                          diagnostics: dependencies.diagnostics,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AsrEndToEndSmokeTestCard(
                          smokeTestService: dependencies.smokeTestService,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small heading above a group of settings cards.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
