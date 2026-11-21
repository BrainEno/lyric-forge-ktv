import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/online/online_lyric_query.dart';
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

  LyricAutoProofreadFlow({
    required this.host,
    required this.service,
    required this.reviewReference,
    required this.pasteReference,
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
    var query = AutoProofreadService.queryFor(
      projectName: project.name,
      artist: project.artist,
      audioDuration: project.audioAsset?.duration,
    );
    while (true) {
      final outcome = await _search(messenger, document, query);
      if (!context.mounted || !host.proofreadIsCurrent(revision)) return;
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
