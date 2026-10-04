import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/local_playlist.dart';
import '../../domain/repositories/local_media_collection_repository.dart';

class LocalFavoriteButton extends StatefulWidget {
  final String sourcePath;
  final double? iconSize;

  const LocalFavoriteButton({
    super.key,
    required this.sourcePath,
    this.iconSize,
  });

  @override
  State<LocalFavoriteButton> createState() => _LocalFavoriteButtonState();
}

class _LocalFavoriteButtonState extends State<LocalFavoriteButton> {
  late final LocalMediaCollectionRepository _collections;
  StreamSubscription<int>? _changeSubscription;
  bool _favorite = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _collections = ServiceLocatorGlobal.I.localMediaCollectionRepository;
    _changeSubscription = _collections.changes.listen((_) {
      unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LocalFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_changeSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final value = await _collections.isFavorite(widget.sourcePath);
      if (mounted) setState(() => _favorite = value);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final value = await _collections.toggleFavorite(widget.sourcePath);
      if (mounted) setState(() => _favorite = value);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return SizedBox(
      width: spec.minimumInteractiveExtent,
      height: spec.minimumInteractiveExtent,
      child: IconButton(
        tooltip: _favorite ? '取消收藏' : '收藏歌曲',
        onPressed: _loading ? null : _toggle,
        iconSize: widget.iconSize,
        icon: Icon(
          _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
      ),
    );
  }
}

Future<LocalPlaylist?> showCreateLocalPlaylistDialog(
  BuildContext context, {
  LocalMediaCollectionRepository? repository,
}) async {
  final collections =
      repository ?? ServiceLocatorGlobal.I.localMediaCollectionRepository;
  final controller = TextEditingController();
  String? validationMessage;

  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final spec = AppResponsive.of(dialogContext);
        return AlertDialog(
          insetPadding: EdgeInsets.all(spec.pageGutter),
          title: const Text('新建播放列表'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _collectionDialogWidth(spec, desktopMax: 420),
            ),
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '名称',
                hintText: '例如：深夜、日语练习、店内播放',
                errorText: validationMessage,
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) {
                  setDialogState(
                    () => validationMessage = '请输入播放列表名称',
                  );
                  return;
                }
                Navigator.pop(dialogContext, trimmed);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                minimumSize: Size(0, spec.minimumInteractiveExtent),
              ),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) {
                  setDialogState(
                    () => validationMessage = '请输入播放列表名称',
                  );
                  return;
                }
                Navigator.pop(dialogContext, trimmed);
              },
              style: FilledButton.styleFrom(
                minimumSize: Size(0, spec.minimumInteractiveExtent),
              ),
              child: const Text('创建'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();

  if (name == null || name.trim().isEmpty) return null;
  return collections.createPlaylist(name);
}

Future<LocalPlaylist?> showRenameLocalPlaylistDialog(
  BuildContext context,
  LocalPlaylist playlist, {
  LocalMediaCollectionRepository? repository,
}) async {
  final collections =
      repository ?? ServiceLocatorGlobal.I.localMediaCollectionRepository;
  final controller = TextEditingController(text: playlist.name);
  String? validationMessage;

  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final spec = AppResponsive.of(dialogContext);
        return AlertDialog(
          insetPadding: EdgeInsets.all(spec.pageGutter),
          title: const Text('重命名播放列表'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _collectionDialogWidth(spec, desktopMax: 420),
            ),
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '名称',
                errorText: validationMessage,
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) {
                  setDialogState(() => validationMessage = '名称不能为空');
                  return;
                }
                Navigator.pop(dialogContext, trimmed);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                minimumSize: Size(0, spec.minimumInteractiveExtent),
              ),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) {
                  setDialogState(() => validationMessage = '名称不能为空');
                  return;
                }
                Navigator.pop(dialogContext, trimmed);
              },
              style: FilledButton.styleFrom(
                minimumSize: Size(0, spec.minimumInteractiveExtent),
              ),
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();

  if (name == null || name == playlist.name) return playlist;
  return collections.renamePlaylist(playlist.id, name);
}

Future<LocalPlaylist?> showAddToLocalPlaylistDialog(
  BuildContext context, {
  required String sourcePath,
  required String title,
  LocalMediaCollectionRepository? repository,
}) async {
  final collections =
      repository ?? ServiceLocatorGlobal.I.localMediaCollectionRepository;
  final playlists = await collections.getPlaylists();
  if (!context.mounted) return null;

  final selected = await showDialog<Object>(
    context: context,
    builder: (dialogContext) {
      final spec = AppResponsive.of(dialogContext);
      final media = MediaQuery.of(dialogContext);
      final availableHeight = media.size.height -
          media.viewInsets.bottom -
          spec.pageGutter * 2;
      final listMaxHeight = (availableHeight * (spec.isShort ? 0.48 : 0.58))
          .clamp(160.0, 420.0)
          .toDouble();

      return AlertDialog(
        insetPadding: EdgeInsets.all(spec.pageGutter),
        title: Text(
          '将“$title”加入播放列表',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _collectionDialogWidth(spec, desktopMax: 460),
          ),
          child: playlists.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('还没有播放列表。可以先创建一个。'),
                )
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: listMaxHeight),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        minTileHeight: spec.minimumInteractiveExtent,
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${playlist.sourcePaths.length} 首歌曲',
                        ),
                        onTap: () => Navigator.pop(dialogContext, playlist),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            child: const Text('取消'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              _CreatePlaylistIntent.instance,
            ),
            style: TextButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(spec.isCompact ? '新建' : '新建播放列表'),
          ),
        ],
      );
    },
  );

  if (!context.mounted || selected == null) return null;
  LocalPlaylist? playlist;
  if (selected is LocalPlaylist) {
    playlist = selected;
  } else if (selected == _CreatePlaylistIntent.instance) {
    playlist = await showCreateLocalPlaylistDialog(
      context,
      repository: collections,
    );
  }
  if (playlist == null) return null;

  return collections.addToPlaylist(playlist.id, [sourcePath]);
}

double _collectionDialogWidth(
  AppLayoutSpec spec, {
  required double desktopMax,
}) {
  if (!spec.isCompact) return desktopMax;
  return (spec.width - spec.pageGutter * 2)
      .clamp(260.0, desktopMax)
      .toDouble();
}

class _CreatePlaylistIntent {
  static const instance = _CreatePlaylistIntent._();
  const _CreatePlaylistIntent._();
}
