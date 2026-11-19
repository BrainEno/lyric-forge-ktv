import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/playback_session_service.dart';
import 'playback_error_banner.dart';
import 'seekable_progress_bar.dart';
import 'transport_bar.dart';

/// Where the project player's transport sits.
enum ProjectPlayerTransportLayout {
  /// The left pane of the two-pane player: large cover, centred identity.
  sidePane,

  /// Above the lyrics on narrower windows: small cover beside the identity,
  /// controls below.
  header,

  /// Above the lyrics in short windows: one row with cover, identity and
  /// compact controls, then the progress bar.
  shortHeader;

  /// The layout for a player whose own box is described by [spec].
  static ProjectPlayerTransportLayout forSpec(AppLayoutSpec spec) {
    if (spec.supportsTwoPane) return sidePane;
    if (spec.isShort) return shortHeader;
    return header;
  }

  bool get isCompact => this != sidePane;
}

/// What the transport shows.
@immutable
class ProjectPlayerTransportState {
  const ProjectPlayerTransportState({
    required this.project,
    required this.playback,
    required this.session,
    required this.availableSources,
    required this.ktvMode,
  });

  final ProjectManifest project;
  final PlaybackState playback;
  final PlaybackSessionState session;

  /// Original, instrumental and vocal tracks the project has; the source
  /// chips appear only when there is a choice.
  final List<AudioSourceType> availableSources;
  final bool ktvMode;

  bool get canChooseSource => availableSources.length > 1;
}

/// What the transport's controls do.
@immutable
class ProjectPlayerTransportActions {
  const ProjectPlayerTransportActions({
    required this.onPlayPause,
    required this.onSeek,
    required this.onSwitchSource,
    required this.onSkipPrevious,
    required this.onSkipNext,
    required this.onModeChanged,
    this.onOpenFullScreenKtv,
  });

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;

  /// True switches to the KTV lyric view, false back to the normal one.
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenFullScreenKtv;
}

/// Cover, song identity, progress, play controls, source and mode chips of
/// the project player, in one of three [ProjectPlayerTransportLayout]s.
///
/// The player screen used to build these three arrangements in two private
/// widgets that each took the same twelve parameters and repeated the
/// progress, controls, source and mode rows, with a fourth wrapper just to
/// feed `TransportBar` (audit: player family, "同文件两套传输控制"). The
/// arrangements now share one state, one set of actions and one set of
/// parts.
class ProjectPlayerTransport extends StatelessWidget {
  const ProjectPlayerTransport({
    super.key,
    required this.state,
    required this.actions,
    required this.layout,
  });

  final ProjectPlayerTransportState state;
  final ProjectPlayerTransportActions actions;
  final ProjectPlayerTransportLayout layout;

  static const String unknownArtist = '未知艺术家';

  /// Chip label of an audio source.
  static String sourceLabel(AudioSourceType source) {
    return switch (source) {
      AudioSourceType.original => '原声',
      AudioSourceType.instrumental => '伴奏',
      AudioSourceType.vocals => '人声',
    };
  }

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      ProjectPlayerTransportLayout.sidePane => _sidePane(context),
      ProjectPlayerTransportLayout.header => _header(context),
      ProjectPlayerTransportLayout.shortHeader => _shortHeader(context),
    };
  }

  Widget _sidePane(BuildContext context) {
    final spec = AppResponsive.of(context);
    final padding = spec.pageGutter.clamp(16, 28).toDouble();
    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: spec.playerArtworkMaxExtent.clamp(220, 320).toDouble(),
            ),
            child: _cover(compact: false),
          ),
        ),
        SizedBox(height: spec.sectionGap),
        _SongIdentity(project: state.project),
        ..._error(AppSpacing.md),
        SizedBox(height: spec.sectionGap),
        SeekableProgressBar(state: state.playback, onSeek: actions.onSeek),
        const SizedBox(height: AppSpacing.md),
        _controls(compact: false),
        if (state.canChooseSource) ...[
          const SizedBox(height: AppSpacing.md),
          _sources(compact: false),
        ],
        SizedBox(height: spec.sectionGap),
        _modes(compact: false),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final spec = AppResponsive.of(context);
    final padding = spec.isCompact ? 12.0 : 16.0;
    final coverExtent = spec.isCompact ? 56.0 : 64.0;
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: coverExtent,
                child: _cover(compact: true),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _SongIdentity(project: state.project, compact: true),
              ),
            ],
          ),
          ..._error(AppSpacing.sm),
          const SizedBox(height: AppSpacing.sm),
          _progress(compact: true),
          const SizedBox(height: AppSpacing.xs),
          _controls(compact: true),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (state.canChooseSource) _sources(compact: true),
              _modes(compact: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shortHeader(BuildContext context) {
    final spec = AppResponsive.of(context);
    final padding = spec.isCompact ? 12.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 6, padding, 8),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox.square(dimension: 48, child: _cover(compact: true)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SongIdentity(project: state.project, compact: true),
              ),
              const SizedBox(width: AppSpacing.xs),
              _controls(compact: true),
            ],
          ),
          ..._error(6),
          _progress(compact: true),
          const SizedBox(height: 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.canChooseSource) ...[
                  _sources(compact: true),
                  const SizedBox(width: AppSpacing.sm),
                ],
                _modes(compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover({required bool compact}) {
    return _ProjectArtwork(
      path: state.project.audioAsset?.thumbnailPath,
      loading: state.playback.isLoading,
      compact: compact,
    );
  }

  List<Widget> _error(double gap) {
    final message = state.playback.error;
    if (message == null) return const [];
    return [SizedBox(height: gap), PlaybackErrorBanner(message: message)];
  }

  Widget _progress({required bool compact}) {
    return SeekableProgressBar(
      state: state.playback,
      onSeek: actions.onSeek,
      compact: compact,
    );
  }

  Widget _controls({required bool compact}) {
    final session = state.session;
    return TransportBar(
      compact: compact,
      isPlaying: state.playback.isPlaying,
      isBusy: state.playback.isBuffering,
      onPlayPause: actions.onPlayPause,
      onPrevious: session.canSkipPrevious ? actions.onSkipPrevious : null,
      onNext: session.canSkipNext ? actions.onSkipNext : null,
    );
  }

  Widget _sources({required bool compact}) {
    return _AudioSourceSelector(
      availableSources: state.availableSources,
      currentSource: state.playback.currentSource,
      onSourceChanged: actions.onSwitchSource,
      compact: compact,
    );
  }

  Widget _modes({required bool compact}) {
    return _PlayerModeControls(
      ktvMode: state.ktvMode,
      hasLyrics: state.project.hasLyrics,
      onModeChanged: actions.onModeChanged,
      onOpenFullScreenKtv: actions.onOpenFullScreenKtv,
      compact: compact,
    );
  }
}

class _ProjectArtwork extends StatelessWidget {
  final String? path;
  final bool loading;
  final bool compact;

  const _ProjectArtwork({
    this.path,
    required this.loading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // The shared cover falls back to its placeholder when the file is
    // missing or cannot be decoded; a raw Image.file showed a broken image
    // (audit C-04). The accent icon still marks a song that is loading.
    return AspectRatio(
      aspectRatio: 1,
      child: AppArtwork(
        path: path,
        borderRadius: compact
            ? AppSpacing.radiusMedium
            : AppSpacing.radiusXLarge,
        placeholderColor: loading ? AppColors.accent : null,
      ),
    );
  }
}

class _SongIdentity extends StatelessWidget {
  final ProjectManifest project;
  final bool compact;

  const _SongIdentity({required this.project, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final artist = project.artist?.trim();
    final album = project.album?.trim();
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          project.name,
          textAlign: compact ? TextAlign.left : TextAlign.center,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (!spec.isShort) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            artist != null && artist.isNotEmpty
                ? artist
                : ProjectPlayerTransport.unknownArtist,
            textAlign: compact ? TextAlign.left : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (!compact && album != null && album.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            album,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _AudioSourceSelector extends StatelessWidget {
  final List<AudioSourceType> availableSources;
  final AudioSourceType? currentSource;
  final ValueChanged<AudioSourceType> onSourceChanged;
  final bool compact;

  const _AudioSourceSelector({
    required this.availableSources,
    required this.currentSource,
    required this.onSourceChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final source in availableSources)
          ChoiceChip(
            selected: source == currentSource,
            onSelected: (_) => onSourceChanged(source),
            visualDensity: compact ? VisualDensity.compact : null,
            label: Text(ProjectPlayerTransport.sourceLabel(source)),
          ),
      ],
    );
  }
}

class _PlayerModeControls extends StatelessWidget {
  final bool ktvMode;
  final bool hasLyrics;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenFullScreenKtv;
  final bool compact;

  const _PlayerModeControls({
    required this.ktvMode,
    required this.hasLyrics,
    required this.onModeChanged,
    required this.onOpenFullScreenKtv,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          selected: !ktvMode,
          visualDensity: compact ? VisualDensity.compact : null,
          onSelected: (_) => onModeChanged(false),
          avatar: const Icon(Icons.library_music_outlined, size: 17),
          label: const Text('普通'),
        ),
        ChoiceChip(
          selected: ktvMode,
          visualDensity: compact ? VisualDensity.compact : null,
          onSelected: hasLyrics ? (_) => onModeChanged(true) : null,
          avatar: const Icon(Icons.mic_rounded, size: 17),
          label: const Text('KTV'),
        ),
        if (hasLyrics)
          OutlinedButton.icon(
            onPressed: onOpenFullScreenKtv,
            icon: const Icon(Icons.fullscreen_rounded, size: 18),
            label: Text(spec.isCompact || spec.isShort ? '全屏' : '全屏 KTV'),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
          ),
      ],
    );
  }
}
