import 'package:flutter/material.dart';

import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../settings_screen_dependencies.dart';
import '../widgets/ai_transcription_settings_section.dart';
import '../widgets/appearance_settings_card.dart';
import '../widgets/asr_end_to_end_smoke_test_card.dart';
import '../widgets/diagnostics_settings_card.dart';
import '../widgets/getting_started_settings_card.dart';
import '../widgets/library_folder_settings_card.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/settings_columns.dart';

/// The line under the app bar. It names only what the page holds; the
/// navigation tooltip used to promise playback and storage settings that do
/// not exist (audit SE-01).
const String settingsIntro = '外观、曲库目录、本地 AI 识别环境，以及出问题时的诊断与试识别。';

/// The same line on a phone, which has no recognition (D-058).
const String mobileSettingsIntro = '外观、曲库目录，以及出问题时的诊断。';

class SettingsScreen extends StatelessWidget {
  final SettingsScreenDependencies dependencies;

  const SettingsScreen({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final libraryFolder = dependencies.libraryFolder;
    final appearance = dependencies.appearance;
    final showGettingStarted = dependencies.showGettingStarted;
    // A phone cannot run the recognition models (D-058): no AI 识别 group
    // and no trial recognition.
    final recognition = AppCapabilities.lyricWorkbench;

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
                    recognition ? settingsIntro : mobileSettingsIntro,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SettingsColumns(
                    primary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // First: the one setting every user meets, on the
                        // phone as on the desktop (decision D-042).
                        if (appearance != null) ...[
                          const SettingsGroupLabel(
                            key: ValueKey('settings-group:appearance'),
                            label: AppearanceSettingsText.group,
                          ),
                          SettingsSectionCard(
                            icon: Icons.palette_outlined,
                            title: AppearanceSettingsText.title,
                            subtitle: AppearanceSettingsText.subtitle,
                            child: AppearanceSettingsCard(
                              controller: appearance,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
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
                        if (recognition) ...[
                          const SettingsGroupLabel(
                            key: ValueKey('settings-group:recognition'),
                            label: 'AI 识别',
                          ),
                          AiTranscriptionSettingsSection(
                            dependencies:
                                dependencies.asrRuntimeSetupDependencies,
                          ),
                        ],
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
                        if (recognition) ...[
                          const SizedBox(height: AppSpacing.lg),
                          AsrEndToEndSmokeTestCard(
                            smokeTestService: dependencies.smokeTestService,
                          ),
                        ],
                        // The checklist of the desktop dashboard (D-070) or
                        // of the phone's 听歌 page (D-071).
                        if (showGettingStarted != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const SettingsGroupLabel(
                            key: ValueKey('settings-group:help'),
                            label: GettingStartedSettingsText.group,
                          ),
                          SettingsSectionCard(
                            icon: Icons.flag_outlined,
                            title: GettingStartedSettingsText.title,
                            subtitle: recognition
                                ? GettingStartedSettingsText.subtitle
                                : GettingStartedSettingsText.mobileSubtitle,
                            child: GettingStartedSettingsCard(
                              onShow: showGettingStarted,
                            ),
                          ),
                        ],
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
