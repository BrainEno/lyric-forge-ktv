import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';

/// Lyric editor screen - manual entry and editing of synced lyrics.
/// Supports time-stamped line editing, chorus marking, and global offset.
class LyricEditorScreen extends StatefulWidget {
  final String projectId;

  const LyricEditorScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<LyricEditorScreen> createState() => _LyricEditorScreenState();
}

class _LyricEditorScreenState extends State<LyricEditorScreen> {
  late final ProjectRepository _repository;
  late Future<ProjectManifest?> _projectFuture;
  LyricDocument? _editingDocument;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _loadProject();
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  Future<void> _saveChanges(ProjectManifest project) async {
    if (_editingDocument == null) return;

    final updated = project.copyWith(
      lyricDocument: _editingDocument,
      status: ProjectStatus.editing,
      currentStage: ProcessingStage.lyricsEdited,
    );

    await _repository.updateProject(updated);

    setState(() {
      _hasChanges = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('歌词已保存'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _addNewLine() {
    setState(() {
      final lines = List<LyricLine>.from(_editingDocument?.lines ?? []);
      final lastEndTime = lines.isNotEmpty
          ? lines.last.endTime
          : const Duration(seconds: 5);

      lines.add(LyricLine(
        text: '',
        startTime: lastEndTime,
        endTime: lastEndTime + const Duration(seconds: 5),
      ));

      _editingDocument = LyricDocument(
        language: _editingDocument?.language ?? 'zh',
        lines: lines,
        globalOffset: _editingDocument?.globalOffset,
      );
      _hasChanges = true;
    });
  }

  void _updateLine(int index, LyricLine updatedLine) {
    setState(() {
      final lines = List<LyricLine>.from(_editingDocument!.lines);
      lines[index] = updatedLine;
      _editingDocument = _editingDocument!.copyWith(lines: lines);
      _hasChanges = true;
    });
  }

  void _deleteLine(int index) {
    setState(() {
      final lines = List<LyricLine>.from(_editingDocument!.lines);
      lines.removeAt(index);
      _editingDocument = _editingDocument!.copyWith(lines: lines);
      _hasChanges = true;
    });
  }

  void _updateGlobalOffset(Duration offset) {
    setState(() {
      _editingDocument = _editingDocument?.copyWith(globalOffset: offset);
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProjectManifest?>(
      future: _projectFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingState();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(onRetry: () => setState(_loadProject));
        }

        final project = snapshot.data!;

        // Initialize editing document if not set
        _editingDocument ??= project.lyricDocument ??
            const LyricDocument(
              language: 'zh',
              lines: [],
            );

        return _LyricEditorContent(
          project: project,
          document: _editingDocument!,
          hasChanges: _hasChanges,
          onSave: () => _saveChanges(project),
          onAddLine: _addNewLine,
          onUpdateLine: _updateLine,
          onDeleteLine: _deleteLine,
          onUpdateOffset: _updateGlobalOffset,
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('编辑歌词')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('编辑歌词')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text('加载失败'),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _LyricEditorContent extends StatelessWidget {
  final ProjectManifest project;
  final LyricDocument document;
  final bool hasChanges;
  final VoidCallback onSave;
  final VoidCallback onAddLine;
  final Function(int, LyricLine) onUpdateLine;
  final Function(int) onDeleteLine;
  final Function(Duration) onUpdateOffset;

  const _LyricEditorContent({
    required this.project,
    required this.document,
    required this.hasChanges,
    required this.onSave,
    required this.onAddLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onUpdateOffset,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = (duration.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds.$millis';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('编辑歌词'),
        backgroundColor: AppColors.bgBase,
        actions: [
          if (hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TextButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save, size: 20),
                label: const Text('保存'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Global offset control
          _GlobalOffsetControl(
            offset: document.globalOffset ?? Duration.zero,
            onChanged: onUpdateOffset,
            formatDuration: _formatDuration,
          ),

          // Lyrics list
          Expanded(
            child: document.lines.isEmpty
                ? _EmptyLyricsState(onAddLine: onAddLine)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: document.lines.length,
                    onReorder: (oldIndex, newIndex) {
                      // Reorder functionality would go here
                    },
                    itemBuilder: (context, index) {
                      final line = document.lines[index];
                      return _LyricLineEditor(
                        key: ValueKey('line_$index'),
                        index: index,
                        line: line,
                        onUpdate: (updated) => onUpdateLine(index, updated),
                        onDelete: () => onDeleteLine(index),
                        formatDuration: _formatDuration,
                      );
                    },
                  ),
          ),

          // Bottom toolbar
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              border: Border(
                top: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Text(
                    '${document.lines.length} 行歌词',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: onAddLine,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('添加行'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalOffsetControl extends StatelessWidget {
  final Duration offset;
  final ValueChanged<Duration> onChanged;
  final String Function(Duration) formatDuration;

  const _GlobalOffsetControl({
    required this.offset,
    required this.onChanged,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '全局偏移',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          Text(
            formatDuration(offset),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: () => onChanged(offset - const Duration(milliseconds: 100)),
            icon: const Icon(Icons.remove),
            iconSize: 20,
          ),
          IconButton(
            onPressed: () => onChanged(offset + const Duration(milliseconds: 100)),
            icon: const Icon(Icons.add),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}

class _EmptyLyricsState extends StatelessWidget {
  final VoidCallback onAddLine;

  const _EmptyLyricsState({required this.onAddLine});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '暂无歌词',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '点击下方按钮添加第一行歌词',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: onAddLine,
            icon: const Icon(Icons.add),
            label: const Text('添加歌词行'),
          ),
        ],
      ),
    );
  }
}

class _LyricLineEditor extends StatefulWidget {
  final int index;
  final LyricLine line;
  final ValueChanged<LyricLine> onUpdate;
  final VoidCallback onDelete;
  final String Function(Duration) formatDuration;

  const _LyricLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.onUpdate,
    required this.onDelete,
    required this.formatDuration,
  });

  @override
  State<_LyricLineEditor> createState() => _LyricLineEditorState();
}

class _LyricLineEditorState extends State<_LyricLineEditor> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.line.text);
  }

  @override
  void didUpdateWidget(covariant _LyricLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.text != widget.line.text &&
        _textController.text != widget.line.text) {
      _textController.text = widget.line.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _updateText(String text) {
    widget.onUpdate(widget.line.copyWith(text: text));
  }

  void _updateStartTime(Duration newTime) {
    widget.onUpdate(widget.line.copyWith(startTime: newTime));
  }

  void _updateEndTime(Duration newTime) {
    widget.onUpdate(widget.line.copyWith(endTime: newTime));
  }

  void _toggleChorus() {
    widget.onUpdate(widget.line.copyWith(isChorus: !widget.line.isChorus));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: widget.line.isChorus
            ? AppColors.accent.withAlpha(13)
            : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: widget.line.isChorus
            ? Border.all(color: AppColors.accent.withAlpha(77))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row header with index and time
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Center(
                  child: Text(
                    '${widget.index + 1}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Time controls
              _TimeControl(
                label: '开始',
                time: widget.line.startTime,
                onChanged: _updateStartTime,
                formatDuration: widget.formatDuration,
              ),
              const SizedBox(width: AppSpacing.md),
              _TimeControl(
                label: '结束',
                time: widget.line.endTime,
                onChanged: _updateEndTime,
                formatDuration: widget.formatDuration,
              ),

              const Spacer(),

              // Chorus toggle
              IconButton(
                onPressed: _toggleChorus,
                icon: Icon(
                  Icons.queue_music,
                  color: widget.line.isChorus
                      ? AppColors.accent
                      : AppColors.textTertiary,
                  size: 20,
                ),
                tooltip: '副歌',
              ),

              // Delete button
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.error,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // Text input
          TextField(
            controller: _textController,
            onChanged: _updateText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: widget.line.isChorus ? AppColors.accent : null,
                  fontWeight:
                      widget.line.isChorus ? FontWeight.w600 : FontWeight.normal,
                ),
            decoration: InputDecoration(
              hintText: '输入歌词...',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeControl extends StatelessWidget {
  final String label;
  final Duration time;
  final ValueChanged<Duration> onChanged;
  final String Function(Duration) formatDuration;

  const _TimeControl({
    required this.label,
    required this.time,
    required this.onChanged,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
        ),
        const SizedBox(width: AppSpacing.xs),
        GestureDetector(
          onTap: () => _showTimePicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
            child: Text(
              formatDuration(time),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ),
      ],
    );
  }

  void _showTimePicker(BuildContext context) {
    // Simple time adjustment dialog
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLarge),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '调整$label时间',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _TimeAdjustButton(
                      label: '-1s',
                      onPressed: () {
                        onChanged(time - const Duration(seconds: 1));
                        Navigator.pop(context);
                      },
                    ),
                    _TimeAdjustButton(
                      label: '-0.1s',
                      onPressed: () {
                        onChanged(time - const Duration(milliseconds: 100));
                        Navigator.pop(context);
                      },
                    ),
                    _TimeAdjustButton(
                      label: '+0.1s',
                      onPressed: () {
                        onChanged(time + const Duration(milliseconds: 100));
                        Navigator.pop(context);
                      },
                    ),
                    _TimeAdjustButton(
                      label: '+1s',
                      onPressed: () {
                        onChanged(time + const Duration(seconds: 1));
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimeAdjustButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _TimeAdjustButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, 48),
      ),
      child: Text(label),
    );
  }
}
