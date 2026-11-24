import 'dart:async';

import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../widgets/project_save_conflict_dialog.dart';
import 'lyric_editor_document_controller.dart';

/// Saving the editor's draft (D-073): one write at a time, guarded by the
/// project's revision, with the conflict dialog when someone else saved first.
///
/// The screen asks for a save and shows the project this hands back; the
/// rules — what counts as clean, what a conflict offers, what is said to the
/// user — live here.
class LyricEditorSaveFlow {
  LyricEditorSaveFlow({
    required this.repository,
    required this.projectId,
    required this.editor,
    required this.context,
    required this.isMounted,
    required this.onProjectChanged,
    required this.onSavingChanged,
  });

  final ProjectRepository repository;
  final String projectId;
  final LyricEditorDocumentController editor;

  /// Where the dialog and messages are shown.
  final BuildContext Function() context;

  /// Whether the editor is still on screen.
  final bool Function() isMounted;

  /// A save or a reload produced a newer project for the screen to show.
  final void Function(ProjectManifest project) onProjectChanged;

  /// A save started or finished; the save button follows [isSaving].
  final VoidCallback onSavingChanged;

  static const String _projectGone = '工程已不存在；当前编辑仍保留，未保存。';

  /// The revision the next write expects to replace; set from the loaded
  /// project and from each write.
  int? projectRevision;

  Future<bool>? _inFlight;

  /// A save is running.
  bool get isSaving => _inFlight != null;

  /// Saves the current draft. Completes with `true` only when the document the
  /// user is looking at has been persisted and nothing newer is pending, so a
  /// caller such as "保存并返回" may leave the editor. Concurrent requests (a
  /// second click, Ctrl+S during the back dialog) share the in-flight save.
  Future<bool> save(ProjectManifest project) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final save = _perform(project);
    _inFlight = save;
    onSavingChanged();
    unawaited(_clearWhenDone(save));
    return save;
  }

  Future<void> _clearWhenDone(Future<bool> save) async {
    try {
      await save;
    } catch (_) {
      // The caller of save observes and reports the failure.
    } finally {
      if (identical(_inFlight, save)) _inFlight = null;
      if (isMounted()) onSavingChanged();
    }
  }

  Future<bool> _perform(ProjectManifest project) async {
    if (editor.document == null) return false;
    final editorRevision = editor.documentRevision;
    final updated = _withDraft(project);
    try {
      final saved = await repository.updateProjectIfUnchanged(
        updated,
        expectedRevision: projectRevision ?? project.revision,
      );
      return _finish(saved, editorRevision: editorRevision);
    } on ProjectUpdateConflictException catch (conflict) {
      try {
        return await _resolveConflict(conflict);
      } catch (error) {
        _showFailure(error);
        return false;
      }
    } catch (error) {
      _showFailure(error);
      return false;
    }
  }

  /// [project] carrying the draft, marked as being edited.
  ProjectManifest _withDraft(ProjectManifest project) => project.copyWith(
    lyricDocument: editor.documentForSave(),
    status: ProjectStatus.editing,
    currentStage: ProcessingStage.lyricsEdited,
  );

  void _showFailure(Object error) {
    if (!isMounted()) return;
    _show('保存失败：$error。当前编辑仍保留，未保存。');
  }

  void _show(String message, {Duration? duration}) {
    final snackBar = duration == null
        ? SnackBar(content: Text(message))
        : SnackBar(content: Text(message), duration: duration);
    ScaffoldMessenger.of(context()).showSnackBar(snackBar);
  }

  /// Records a completed write. Returns whether the editor is now clean: an
  /// edit made while the write was pending is newer than what reached disk and
  /// must stay marked unsaved.
  bool _finish(ProjectManifest saved, {required int editorRevision}) {
    if (!isMounted()) return false;
    projectRevision = saved.revision;
    final clean = editor.markSavedIfUnchanged(editorRevision);
    onProjectChanged(saved);
    // Saving answers at once, even over an undo offer for a deleted row.
    ScaffoldMessenger.of(context()).removeCurrentSnackBar();
    _show(
      clean ? '歌词已保存' : '已保存，但保存期间的新修改尚未保存。',
      duration: const Duration(seconds: 2),
    );
    return clean;
  }

  Future<bool> _resolveConflict(ProjectUpdateConflictException conflict) async {
    final latest =
        conflict.currentProject ?? await repository.getProjectById(projectId);
    if (!isMounted()) return false;
    if (latest == null) {
      _show(_projectGone);
      return false;
    }

    final choice = await showProjectSaveConflictDialog(
      context(),
      latestRevision: latest.revision,
    );
    if (!isMounted()) return false;

    switch (choice) {
      case ProjectSaveConflictChoice.keepEditing:
        return false;
      case ProjectSaveConflictChoice.reloadLatest:
        final reloaded = await repository.getProjectById(projectId);
        if (!isMounted()) return false;
        if (reloaded == null) {
          _show(_projectGone);
          return false;
        }
        projectRevision = reloaded.revision;
        editor.load(
          reloaded.lyricDocument ??
              const LyricDocument(language: 'zh', lines: <LyricLine>[]),
        );
        onProjectChanged(reloaded);
        _show('已载入最新版工程。');
        // The user chose to see the latest version, not to leave with it.
        return false;
      case ProjectSaveConflictChoice.overwriteLatest:
        final editorRevision = editor.documentRevision;
        try {
          final saved = await repository.updateProjectIfUnchanged(
            _withDraft(latest),
            expectedRevision: latest.revision,
          );
          return _finish(saved, editorRevision: editorRevision);
        } on ProjectUpdateConflictException catch (newConflict) {
          return _resolveConflict(newConflict);
        }
    }
  }
}
