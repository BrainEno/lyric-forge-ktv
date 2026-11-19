import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../settings_screen_dependencies.dart';
import '../widgets/ai_transcription_settings_section.dart';
import '../widgets/asr_end_to_end_smoke_test_card.dart';
import '../widgets/diagnostics_settings_card.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsScreenDependencies dependencies;

  const SettingsScreen({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);

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
                    '管理 Elysium Player 的本地运行环境与工作流。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AiTranscriptionSettingsSection(
                    dependencies: dependencies.asrRuntimeSetupDependencies,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AsrEndToEndSmokeTestCard(
                    smokeTestService: dependencies.smokeTestService,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DiagnosticsSettingsCard(
                    diagnostics: dependencies.diagnostics,
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
