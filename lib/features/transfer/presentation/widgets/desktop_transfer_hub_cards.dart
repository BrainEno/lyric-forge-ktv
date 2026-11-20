import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import 'desktop_transfer_hub_text.dart';

// The cards of the desktop transfer page.
//
// They lived as private classes at the bottom of the page. Pulled out, the
// page keeps the service and its steps, and these widgets can be tested on
// their own: the waiting card's loading line, the empty library with its way
// out, the address list with readable network names.

/// What Media Hub shares and with whom; always shown first.
class DesktopHubSecurityNotice extends StatelessWidget {
  const DesktopHubSecurityNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.shield_outlined, color: AppColors.warning),
        title: Text(DesktopTransferHubText.securityTitle),
        subtitle: Text(DesktopTransferHubText.securityMessage),
      ),
    );
  }
}

/// Whether the service runs, with the start, stop and refresh buttons.
class DesktopHubOverviewCard extends StatelessWidget {
  const DesktopHubOverviewCard({
    super.key,
    required this.running,
    required this.initializing,
    required this.busy,
    required this.trackCount,
    required this.onStart,
    required this.onStop,
    required this.onRefresh,
  });

  final bool running;
  final bool initializing;
  final bool busy;
  final int trackCount;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tone = running ? AppColors.success : AppColors.accent;
    final working = busy || initializing;
    VoidCallback? primary;
    if (!working) primary = running ? onStop : onStart;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tone.withAlpha(20),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                  ),
                  child: Icon(
                    running ? Icons.sync_alt_rounded : Icons.devices_rounded,
                    color: tone,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running
                            ? DesktopTransferHubText.runningTitle
                            : DesktopTransferHubText.stoppedTitle,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DesktopTransferHubText.overviewStatus(
                          initializing: initializing,
                          running: running,
                          trackCount: trackCount,
                        ),
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: primary,
                  icon: working
                      ? const AppButtonSpinner()
                      : Icon(
                          running
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  label: Text(
                    running
                        ? DesktopTransferHubText.stop
                        : DesktopTransferHubText.start,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: working ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(DesktopTransferHubText.refresh),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The QR code, the pairing link to copy and the addresses a phone can use.
class DesktopHubPairingCard extends StatelessWidget {
  const DesktopHubPairingCard({
    super.key,
    required this.session,
    required this.onCopy,
  });

  final MediaHubSession session;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final text = Theme.of(context).textTheme;
    final qr = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: QrImageView(
        data: session.pairingUri.toString(),
        size: layout.isCompact ? 180 : 220,
        backgroundColor: AppColors.pureWhite,
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DesktopTransferHubText.scanStep,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          DesktopTransferHubText.scanHint,
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          DesktopTransferHubText.copyStep,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: SelectableText(
            session.pairingUri.toString(),
            style: text.bodySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded),
          label: const Text(DesktopTransferHubText.copy),
        ),
        if (session.endpoints.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(DesktopTransferHubText.endpointsTitle, style: text.labelLarge),
          const SizedBox(height: 4),
          for (final endpoint in session.endpoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                DesktopTransferHubText.endpoint(endpoint),
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: layout.isCompactOrMedium
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: qr),
                  const SizedBox(height: AppSpacing.lg),
                  details,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  qr,
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: details),
                ],
              ),
      ),
    );
  }
}

/// Where the QR code goes while the service is off or starting.
///
/// It showed a bare spinner, with "正在读取电脑音乐库…" even while the
/// service was starting; it now says which of the two is happening, and
/// its start button waits while another step runs.
class DesktopHubWaitingCard extends StatelessWidget {
  const DesktopHubWaitingCard({
    super.key,
    required this.loadingMessage,
    required this.onStart,
  });

  /// What is happening, or null when the service is simply off.
  final String? loadingMessage;

  /// Null while another step runs.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final loading = loadingMessage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: loading != null
            ? Center(child: AppInlineLoading(message: loading))
            : Column(
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 56,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    DesktopTransferHubText.waitingMessage,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text(DesktopTransferHubText.startAndPair),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One transfer direction and what it does right now.
class DesktopHubDirectionCard extends StatelessWidget {
  const DesktopHubDirectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withAlpha(18),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: Icon(icon, color: AppColors.accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
      ),
    );
  }
}

/// A preview of the songs this computer shares.
///
/// An empty library was one plain sentence that sent the user to a button
/// further up; it is now the shared empty state with both ways out in it:
/// open the library to import songs, or refresh after importing. While the
/// library is first read it says so instead of claiming "0 首".
class DesktopHubSharedTracksCard extends StatelessWidget {
  const DesktopHubSharedTracksCard({
    super.key,
    required this.tracks,
    required this.running,
    required this.loading,
    required this.onRefresh,
    required this.onOpenLibrary,
  });

  final List<SharedAudioTrack> tracks;
  final bool running;

  /// The library is being read for the first time.
  final bool loading;

  /// Null while another step runs.
  final VoidCallback? onRefresh;
  final VoidCallback onOpenLibrary;

  static const Key emptyKey = ValueKey('desktop-hub:tracks-empty');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const limit = DesktopTransferHubText.previewLimit;
    final visible = tracks.take(limit).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DesktopTransferHubText.tracksTitle(tracks.length),
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    running
                        ? DesktopTransferHubText.reachable
                        : DesktopTransferHubText.stopped,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              DesktopTransferHubText.tracksCaption,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: AppInlineLoading(
                    message: DesktopTransferHubText.libraryLoading,
                  ),
                ),
              )
            else if (tracks.isEmpty)
              AppEmptyState(
                key: emptyKey,
                icon: Icons.library_music_outlined,
                title: DesktopTransferHubText.tracksEmptyTitle,
                message: DesktopTransferHubText.tracksEmptyMessage,
                density: AppEmptyStateDensity.panel,
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: onOpenLibrary,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text(DesktopTransferHubText.openLibrary),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(DesktopTransferHubText.refresh),
                  ),
                ],
              )
            else ...[
              for (final track in visible)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(trackDetails(track)),
                ),
              if (tracks.length > visible.length)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    DesktopTransferHubText.moreTracks(
                      tracks.length - visible.length,
                    ),
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Artist, format and size of a previewed song.
  static String trackDetails(SharedAudioTrack track) => [
    if (track.artist?.trim().isNotEmpty == true) track.artist!.trim(),
    track.format.toUpperCase(),
    DesktopTransferHubText.fileSize(track.byteLength),
  ].join(' · ');
}
