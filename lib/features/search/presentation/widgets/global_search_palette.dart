import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_command_keys.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/global_search_index.dart';
import '../../domain/global_search_item.dart';
import '../../domain/global_search_source.dart';
import '../global_search_dependencies.dart';
import 'keyboard_shortcuts_panel.dart';

/// What was picked in the search: a result, and whether with the second
/// action (Shift+Enter or the row's button).
class GlobalSearchChoice {
  const GlobalSearchChoice(this.hit, {this.secondary = false});

  final GlobalSearchHit hit;
  final bool secondary;
}

/// Opens the global search (D-065) and carries out the pick. Does nothing
/// while the search is already open.
Future<void> showGlobalSearch(
  BuildContext context,
  GlobalSearchDependencies dependencies,
) async {
  if (GlobalSearchPalette.isOpen) return;
  final choice = await showDialog<GlobalSearchChoice>(
    context: context,
    builder: (_) => GlobalSearchPalette(
      source: dependencies.source,
      showKeyHints: !dependencies.phone,
    ),
  );
  if (choice == null || !context.mounted) return;
  await runGlobalSearchChoice(context, dependencies, choice);
}

/// Does what [choice] asks: opens the page, plays or queues the song, opens
/// or plays the playlist, or shows the shortcut panel.
Future<void> runGlobalSearchChoice(
  BuildContext context,
  GlobalSearchDependencies dependencies,
  GlobalSearchChoice choice,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final session = dependencies.playbackSession;
  void tell(String message) {
    messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  switch (choice.hit.item.target) {
    case OpenRouteTarget(:final route):
      dependencies.openRoute(route);
    case PlaySongTarget(:final item):
      if (choice.secondary) {
        await session.enqueue(item);
        tell('已加入播放队列：${item.title}');
      } else {
        await session.setQueue([item]);
      }
    case OpenPlaylistTarget(:final route, :final songs):
      if (!choice.secondary) {
        dependencies.openRoute(route);
      } else if (songs.isEmpty) {
        tell('这个歌单里没有能播放的歌曲');
      } else {
        await session.setQueue(songs);
        tell('正在播放歌单“${choice.hit.item.title}”（${songs.length} 首）');
      }
    case ShowShortcutsTarget():
      await showKeyboardShortcuts(context);
  }
}

/// The search box and its results (D-065).
///
/// Everything is read from [source] when the box opens and searched as the
/// user types. ↑/↓ move the selection, Enter opens it, Shift+Enter takes the
/// second action (queue the song, play the playlist), Esc closes.
class GlobalSearchPalette extends StatefulWidget {
  const GlobalSearchPalette({
    super.key,
    required this.source,
    this.showKeyHints = true,
  });

  static const fieldKey = ValueKey('global-search-field');
  static const emptyKey = ValueKey('global-search-empty');

  /// The key of the row for [hit].
  static ValueKey<String> rowKey(GlobalSearchHit hit) =>
      ValueKey('global-search-row-${hit.kind.name}-${hit.item.id}');

  /// The key of the row's second-action button.
  static ValueKey<String> secondaryKey(GlobalSearchHit hit) =>
      ValueKey('global-search-secondary-${hit.kind.name}-${hit.item.id}');

  static const hint = '搜索工程、歌曲、歌单、歌词或操作';

  static int _mounted = 0;

  /// Whether a search box is on screen, so a second Ctrl+K does not stack
  /// another. Counted by the box itself, so it can never stay stuck.
  static bool get isOpen => _mounted > 0;

  final GlobalSearchSource source;

  /// The footer naming the keys; off on phones.
  final bool showKeyHints;

  /// The second action [hit] offers, as a label, or null for none.
  static String? secondaryLabel(GlobalSearchHit hit) =>
      switch (hit.item.target) {
        PlaySongTarget() => '加入播放队列',
        OpenPlaylistTarget() => '播放歌单',
        _ => null,
      };

  @override
  State<GlobalSearchPalette> createState() => _GlobalSearchPaletteState();
}

class _GlobalSearchPaletteState extends State<GlobalSearchPalette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};

  GlobalSearchIndex? _index;
  Object? _error;
  GlobalSearchResults _results = GlobalSearchResults.empty;
  List<GlobalSearchHit> _hits = const [];
  int _selected = 0;

  static const _queueKey = SingleActivator(
    LogicalKeyboardKey.enter,
    shift: true,
  );

  @override
  void initState() {
    super.initState();
    GlobalSearchPalette._mounted++;
    unawaited(_load());
  }

  @override
  void dispose() {
    GlobalSearchPalette._mounted--;
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await widget.source.load();
      if (!mounted) return;
      _index = GlobalSearchIndex(items);
      _search();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _search() {
    final index = _index;
    if (index == null) return;
    setState(() {
      _results = index.search(_controller.text);
      _hits = _results.hits;
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_hits.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % _hits.length;
      if (_selected < 0) _selected += _hits.length;
    });
    final key = _rowKeys[_keyOf(_hits[_selected])];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = key?.currentContext;
      if (row == null || !row.mounted) return;
      Scrollable.ensureVisible(
        row,
        duration: const Duration(milliseconds: 80),
        alignmentPolicy: delta > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  void _choose(GlobalSearchHit hit, {bool secondary = false}) {
    final second = secondary && GlobalSearchPalette.secondaryLabel(hit) != null;
    Navigator.of(context).pop(GlobalSearchChoice(hit, secondary: second));
  }

  void _chooseSelected({bool secondary = false}) {
    if (_hits.isEmpty) return;
    _choose(_hits[_selected], secondary: secondary);
  }

  String _keyOf(GlobalSearchHit hit) => '${hit.kind.name}:${hit.item.id}';

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.of(context).isCompact;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(compact),
        const Divider(height: 1),
        Flexible(child: _body()),
        if (widget.showKeyHints && !compact) ...[
          const Divider(height: 1),
          const _KeyHints(),
        ],
      ],
    );
    if (compact) {
      return Dialog.fullscreen(
        backgroundColor: AppColors.bgElevated,
        child: SafeArea(child: content),
      );
    }
    return Dialog(
      alignment: Alignment.topCenter,
      backgroundColor: AppColors.bgElevated,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxxl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: content,
      ),
    );
  }

  Widget _field(bool compact) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1),
                _queueKey: () => _chooseSelected(secondary: true),
              },
              child: TextField(
                key: GlobalSearchPalette.fieldKey,
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _search(),
                onSubmitted: (_) => _chooseSelected(),
                decoration: const InputDecoration(
                  hintText: GlobalSearchPalette.hint,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: '清除',
              onPressed: () {
                _controller.clear();
                _search();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          if (compact)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final theme = Theme.of(context);
    final error = _error;
    if (error != null) {
      return _Message(
        icon: Icons.error_outline_rounded,
        title: '没能读取搜索内容',
        detail: '$error',
        action: TextButton(onPressed: _retry, child: const Text('重试')),
      );
    }
    if (_index == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final query = _controller.text.trim();
    if (_results.isEmpty) {
      return query.isEmpty
          ? const _Message(
              icon: Icons.search_rounded,
              title: '输入歌名、歌手、文件名或一句歌词',
            )
          : _Message(
              key: GlobalSearchPalette.emptyKey,
              icon: Icons.search_off_rounded,
              title: '没有找到“$query”',
              detail: '换个关键词试试：歌名、歌手、文件名，或歌词里的一句',
            );
    }
    var position = 0;
    final rows = <Widget>[];
    for (final group in _results.groups) {
      rows.add(
        _GroupHeader(
          label: query.isEmpty ? _browseLabel(group.kind) : group.kind.label,
          hidden: group.hidden,
        ),
      );
      for (final hit in group.hits) {
        final index = position++;
        final rowKey = _rowKeys.putIfAbsent(_keyOf(hit), GlobalKey.new);
        rows.add(
          KeyedSubtree(
            key: rowKey,
            child: _ResultRow(
              key: GlobalSearchPalette.rowKey(hit),
              hit: hit,
              query: query,
              selected: index == _selected,
              onTap: () => _choose(hit),
              onSecondary: GlobalSearchPalette.secondaryLabel(hit) == null
                  ? null
                  : () => _choose(hit, secondary: true),
            ),
          ),
        );
      }
    }
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    );
  }

  static String _browseLabel(GlobalSearchKind kind) => switch (kind) {
    GlobalSearchKind.action => '常用',
    GlobalSearchKind.project => '最近的工程',
    _ => kind.label,
  };
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.hidden});

  final String label;
  final int hidden;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        hidden > 0 ? '$label · 还有 $hidden 个，输入更多字缩小范围' : label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.hit,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onSecondary,
  });

  final GlobalSearchHit hit;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = hit.detail;
    final secondary = GlobalSearchPalette.secondaryLabel(hit);
    return Material(
      color: selected ? AppColors.bgHighlight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: SizedBox.square(
                  dimension: 36,
                  child: Icon(
                    _iconFor(hit),
                    size: AppSpacing.iconSizeSmall,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Highlighted(
                      text: hit.item.title,
                      query: query,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (detail != null)
                      _Highlighted(
                        text: detail,
                        query: hit.lyricLine == null ? '' : query,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (secondary != null && onSecondary != null)
                IconButton(
                  key: GlobalSearchPalette.secondaryKey(hit),
                  tooltip: secondary,
                  onPressed: onSecondary,
                  icon: Icon(
                    hit.item.target is PlaySongTarget
                        ? Icons.playlist_add_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(GlobalSearchHit hit) {
    if (hit.kind == GlobalSearchKind.lyric) return Icons.format_quote_rounded;
    return switch (hit.item.kind) {
      GlobalSearchKind.project => Icons.library_books_outlined,
      GlobalSearchKind.song => Icons.music_note_outlined,
      GlobalSearchKind.playlist => Icons.queue_music_rounded,
      GlobalSearchKind.lyric => Icons.format_quote_rounded,
      GlobalSearchKind.action => switch (hit.item.id) {
        'import' => Icons.add_rounded,
        'projects' => Icons.library_books_outlined,
        'review' => Icons.spellcheck_rounded,
        'library' => Icons.library_music_outlined,
        'artists' => Icons.person_outline_rounded,
        'albums' => Icons.album_outlined,
        'favorites' => Icons.favorite_border_rounded,
        'playlists' => Icons.queue_music_rounded,
        'now-playing' => Icons.graphic_eq_rounded,
        'trash' => Icons.restore_from_trash_outlined,
        'duplicates' => Icons.cleaning_services_outlined,
        'media-sharing' => Icons.phone_iphone_rounded,
        'from-computer' => Icons.computer_rounded,
        'settings' => Icons.settings_outlined,
        'shortcuts' => Icons.keyboard_outlined,
        'home' => Icons.headphones_rounded,
        'lyrics' => Icons.lyrics_outlined,
        _ => Icons.arrow_forward_rounded,
      },
    };
  }
}

/// [text] on one line with the part matching [query] in the accent colour.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query, this.style});

  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final match = findSearchMatch(text, query);
    if (match == null) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, match.start)),
          TextSpan(
            text: text.substring(match.start, match.end),
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(match.end)),
        ],
      ),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppSpacing.iconSizeLarge,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          ?action,
        ],
      ),
    );
  }
}

class _KeyHints extends StatelessWidget {
  const _KeyHints();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.textTertiary,
    );
    final all = AppCommandKeys.withCommand('/', theme.platform);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        '↑↓ 选择 · Enter 打开 · Shift+Enter 加入队列或播放歌单 · Esc 关闭'
        ' · $all 全部快捷键',
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
