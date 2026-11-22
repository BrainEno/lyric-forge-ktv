import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/online/online_lyric_query.dart';
import '../../domain/online/song_tags.dart';
import '../../domain/proofreading/auto_proofread_service.dart';
import '../widgets/auto_proofread_dialogs.dart';
import 'lyric_editor_proofreading_coordinator.dart';

/// The interaction around [AutoProofreadService]: search, ask only when no
/// lyric matched, apply once as one undoable change, and offer the review of
/// what stayed uncertain.
class LyricAutoProofreadFlow {
  final LyricEditorProofreadFlowHost host;
  final AutoProofreadService service;

  /// Opens the reference review for [input] on [document]; used for the rows
  /// the online lyric could not settle.
  final Future<void> Function({
    required LyricDocument document,
    required int revision,
    required ReferenceLyricInput input,
  })
  reviewReference;

  /// Opens the paste-a-lyric flow on [document].
  final Future<void> Function({
    required LyricDocument document,
    required int revision,
  })
  pasteReference;
  final DateTime Function() clock;

  /// Reads the audio file's tags for a second search when the project name
  /// finds nothing (D-055); null searches by the project name only.
  final SongTagReader? tagReader;

  LyricAutoProofreadFlow({
    required this.host,
    required this.service,
    required this.reviewReference,
    required this.pasteReference,
    this.tagReader,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  static bool _asksForFallback(AutoProofreadLyricStatus status) =>
      status == AutoProofreadLyricStatus.noTitle ||
      status == AutoProofreadLyricStatus.notFound ||
      status == AutoProofreadLyricStatus.noMatch;

  Future<void> run({
    required ProjectManifest project,
    required LyricDocument document,
    required int revision,
  }) async {
    final context = host.proofreadContext;
    final messenger = ScaffoldMessenger.of(context);
    final queries = await _queries(project);
    if (!context.mounted || !host.proofreadIsCurrent(revision)) return;
    var query = queries.first;
    final untried = queries.skip(1).toList();
    while (true) {
      final outcome = await _search(messenger, document, query);
      if (!context.mounted || !host.proofreadIsCurrent(revision)) return;
      // The audio tags name the song differently: try them before asking.
      if (_asksForFallback(outcome.lyricStatus) &&
          service.canSearch &&
          untried.isNotEmpty) {
        query = untried.removeAt(0);
        continue;
      }
      if (_asksForFallback(outcome.lyricStatus)) {
        final choice = await showAutoProofreadFallbackDialog(
          context,
          outcome: outcome,
        );
        if (!context.mounted || !host.proofreadIsCurrent(revision)) return;
        switch (choice) {
          case null:
            return;
          case AutoProofreadRetry(query: final retry):
            query = retry;
            untried.clear();
            continue;
          case AutoProofreadPaste():
            await pasteReference(document: document, revision: revision);
            return;
          case AutoProofreadOfflineOnly():
            break;
        }
      }
      if (!context.mounted) return;
      await _apply(context, messenger, outcome);
      return;
    }
  }

  /// The project name first, then the audio tags when they differ; never
  /// empty, so an unsearchable project still reaches the fallback dialog.
  Future<List<OnlineLyricQuery>> _queries(ProjectManifest project) async {
    final primary = AutoProofreadService.queryFor(
      projectName: project.name,
      artist: project.artist,
      audioDuration: project.audioAsset?.duration,
    );
    if (!service.canSearch) return [primary];
    final tags = await readSongTagsSafely(
      tagReader,
      project.audioAsset?.originalPath,
    );
    final candidates = OnlineLyricQuery.candidatesFor(
      name: project.name,
      artist: project.artist,
      duration: project.audioAsset?.duration,
      tags: tags,
    );
    return candidates.isEmpty ? [primary] : candidates;
  }

  Future<AutoProofreadOutcome> _search(
    ScaffoldMessengerState messenger,
    LyricDocument document,
    OnlineLyricQuery query,
  ) async {
    final searching = service.canSearch && query.isSearchable;
    if (searching) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(AutoProofreadStrings.searching(query)),
          duration: const Duration(seconds: 30),
        ),
      );
    }
    try {
      return await service.run(
        draft: document,
        query: query,
        protectedIndices: host.proofreadManuallyEditedLineIndices,
        appliedAt: clock(),
      );
    } finally {
      if (searching) messenger.hideCurrentSnackBar();
    }
  }

  Future<void> _apply(
    BuildContext context,
    ScaffoldMessengerState messenger,
    AutoProofreadOutcome outcome,
  ) async {
    final result = outcome.result;
    if (!result.hasChanges) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AutoProofreadStrings.nothingToDo(outcome)),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      host.applyProofreadDocument(
        document: result.document,
        label: AutoProofreadStrings.actionTitle,
        selectedLineIndex:
            result.firstChangedIndex ?? host.proofreadSelectedLineIndex,
        isReferenceProofread: false,
        message: AutoProofreadStrings.summary(outcome),
      );
    }

    final reference = result.reference;
    if (reference == null ||
        !result.usedReference ||
        result.uncertainLines == 0) {
      return;
    }
    final revision = host.proofreadDocumentRevision;
    final review = await showAutoProofreadUncertainDialog(
      context,
      outcome: outcome,
    );
    if (!review || !context.mounted || !host.proofreadIsCurrent(revision)) {
      return;
    }
    await reviewReference(
      document: result.document,
      revision: revision,
      input: reference.input,
    );
  }
}
