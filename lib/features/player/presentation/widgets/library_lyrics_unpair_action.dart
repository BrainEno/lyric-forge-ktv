import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/library_lyrics_auto_linker.dart';
import '../../domain/services/library_lyrics_pairing.dart';
import 'library_lyrics_link_text.dart';

/// Asks, then takes back the lyrics the library paired with a song by file
/// name (D-034), with a notice that can undo it.
///
/// [onChanged] runs after the song's lyrics changed either way, so the
/// caller can reload what it shows.
Future<void> unpairLibraryLyrics(
  BuildContext context, {
  required LibraryLyricsAutoLinker linker,
  required String audioPath,
  required String songTitle,
  required LibraryLyricsPairing pairing,
  required Future<void> Function() onChanged,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) =>
        LibraryLyricsUnpairDialog(songTitle: songTitle, pairing: pairing),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final LibraryLyricsUnpairResult result;
  try {
    result = await linker.unpair(audioPath);
  } on Exception catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(LibraryLyricsLinkText.unpairFailed(error))),
    );
    return;
  }
  if (result.outcome == LibraryLyricsUnpairOutcome.unpaired) {
    await onChanged();
  }

  Future<void> undo() async {
    final LibraryLyricsLinkResult pass;
    try {
      pass = await linker.pairAgain(audioPath, pairing);
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('没能恢复配对：$error')));
      return;
    }
    await onChanged();
    messenger.showSnackBar(
      SnackBar(
        content: Text(LibraryLyricsLinkText.pairAgainOutcome(songTitle, pass)),
      ),
    );
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(LibraryLyricsLinkText.unpairOutcome(songTitle, result)),
      duration: const Duration(seconds: 8),
      action: result.outcome == LibraryLyricsUnpairOutcome.unpaired
          ? SnackBarAction(label: '撤销', onPressed: () => unawaited(undo()))
          : null,
    ),
  );
}

/// Confirms taking back an automatic lyric pairing: which file, why it was
/// paired, and that the file itself stays. Pops `true` to go ahead.
class LibraryLyricsUnpairDialog extends StatelessWidget {
  const LibraryLyricsUnpairDialog({
    super.key,
    required this.songTitle,
    required this.pairing,
  });

  final String songTitle;
  final LibraryLyricsPairing pairing;

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final theme = Theme.of(context);
    final buttonSize = Size(0, layout.minimumInteractiveExtent);
    final reason = LibraryLyricsLinkText.reasonLabel(pairing.reason);
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('解除歌词配对？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(LibraryLyricsLinkText.unpairQuestion(songTitle, pairing)),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lyrics_outlined,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LibraryLyricsLinkText.fileName(pairing.lyricPath),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '配对依据：$reason',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                LibraryLyricsLinkText.unpairPromise,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: buttonSize),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: buttonSize),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('解除配对'),
        ),
      ],
    );
  }
}
