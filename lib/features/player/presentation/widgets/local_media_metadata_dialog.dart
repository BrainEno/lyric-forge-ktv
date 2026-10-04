import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';

Future<void> showLocalMediaMetadataDialog(
  BuildContext context,
  PlaybackItem item,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LocalMediaMetadataDialog(item: item),
  );
}

class LocalMediaMetadataDialog extends StatefulWidget {
  final PlaybackItem item;

  const LocalMediaMetadataDialog({
    super.key,
    required this.item,
  });

  @override
  State<LocalMediaMetadataDialog> createState() =>
      _LocalMediaMetadataDialogState();
}

class _LocalMediaMetadataDialogState extends State<LocalMediaMetadataDialog> {
  late final LocalMediaMetadataRepository _repository;
  late final PlaybackSessionService _session;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;

  LocalMediaMetadata? _stored;
  String? _previewArtworkPath;
  String? _newArtworkSource;
  bool _removeArtwork = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.localMediaMetadataRepository;
    _session = ServiceLocatorGlobal.I.playbackSessionService;
    _titleController = TextEditingController(text: widget.item.title);
    _artistController = TextEditingController(text: widget.item.artist ?? '');
    _albumController = TextEditingController();
    _previewArtworkPath = widget.item.artworkPath;
    _loadStoredMetadata();
  }

  Future<void> _loadStoredMetadata() async {
    try {
      final stored = await _repository.getForAudio(
        widget.item.audioAsset.originalPath,
      );
      if (!mounted) return;
      setState(() {
        _stored = stored;
        if (stored != null) {
          _titleController.text =
              stored.title?.trim().isNotEmpty == true
                  ? stored.title!
                  : widget.item.title;
          _artistController.text = stored.artist ?? widget.item.artist ?? '';
          _albumController.text = stored.album ?? '';
          _previewArtworkPath =
              stored.artworkPath ?? widget.item.artworkPath;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法读取歌曲资料: $error';
      });
    }
  }

  Future<void> _pickArtwork() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择歌曲封面',
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty || !mounted) return;
    setState(() {
      _newArtworkSource = path;
      _previewArtworkPath = path;
      _removeArtwork = false;
      _error = null;
    });
  }

  void _clearArtwork() {
    setState(() {
      _newArtworkSource = null;
      _previewArtworkPath = null;
      _removeArtwork = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _nullable(_titleController.text);
    if (title == null) {
      setState(() => _error = '歌曲名称不能为空');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      var artworkPath = _stored?.artworkPath;
      if (_removeArtwork) {
        await _repository.removeManagedArtwork(artworkPath);
        artworkPath = null;
      } else if (_newArtworkSource != null) {
        final previousArtwork = artworkPath;
        artworkPath = await _repository.importArtwork(
          sourcePath: widget.item.audioAsset.originalPath,
          imagePath: _newArtworkSource!,
        );
        if (previousArtwork != null && previousArtwork != artworkPath) {
          await _repository.removeManagedArtwork(previousArtwork);
        }
      }

      final metadata = LocalMediaMetadata(
        sourcePath: widget.item.audioAsset.originalPath,
        title: title,
        artist: _nullable(_artistController.text),
        album: _nullable(_albumController.text),
        artworkPath: artworkPath,
        updatedAt: DateTime.now(),
        metadata: {
          ...?_stored?.metadata,
          'titleStorage': 'utf-8-user-override',
        },
      );
      final saved = await _repository.save(metadata);

      final fallbackTitle = _fileTitle(widget.item.audioAsset.originalPath);
      await _session.updateItem(
        widget.item.copyWith(
          title: saved.resolvedTitle(fallbackTitle),
          artist: saved.artist,
          artworkPath: saved.resolvedArtwork(
            widget.item.audioAsset.thumbnailPath,
          ),
          clearArtist: saved.artist == null,
          clearArtwork: saved.artworkPath == null &&
              widget.item.audioAsset.thumbnailPath == null,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存歌曲资料失败: $error';
      });
    }
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _fileTitle(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('编辑歌曲资料'),
      content: SizedBox(
        width: 620,
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ArtworkPreview(path: _previewArtworkPath),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '封面图片',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                '图片会复制到 LyricForge 自己的媒体目录，不修改原音频文件。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _saving ? null : _pickArtwork,
                                    icon: const Icon(Icons.image_outlined),
                                    label: Text(
                                      _previewArtworkPath == null
                                          ? '选择封面'
                                          : '更换封面',
                                    ),
                                  ),
                                  if (_previewArtworkPath != null)
                                    TextButton.icon(
                                      onPressed: _saving ? null : _clearArtwork,
                                      icon: const Icon(Icons.close_rounded),
                                      label: const Text('移除封面'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _titleController,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '歌曲名称',
                        helperText: '支持中文、日文、emoji；以 UTF-8 保存，不写回原文件标签。',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _artistController,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '艺人'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _albumController,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: '专辑'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }
}

class _ArtworkPreview extends StatelessWidget {
  final String? path;

  const _ArtworkPreview({this.path});

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final exists = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: Container(
        width: 132,
        height: 132,
        color: AppColors.bgSurface,
        child: exists
            ? Image.file(file!, fit: BoxFit.cover)
            : const Icon(
                Icons.album_rounded,
                size: 52,
                color: AppColors.textTertiary,
              ),
      ),
    );
  }
}
