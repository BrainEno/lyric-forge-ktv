/// Stands for the command modifier in [KeyboardShortcut.keys]: shown as ⌘
/// on Apple platforms and Ctrl elsewhere.
const String commandKey = 'mod';

const List<String> _redo = [commandKey, 'Shift', 'Z'];
const List<String> _ctrlY = ['Ctrl', 'Y'];

/// One shortcut: the keys pressed together, and what they do.
class KeyboardShortcut {
  const KeyboardShortcut(this.action, this.keys, {this.alternative});

  final String action;

  /// Keys held together, e.g. `[commandKey, 'K']`.
  final List<String> keys;

  /// Another combination for the same action (Ctrl+Y beside Ctrl+Shift+Z).
  final List<String>? alternative;
}

/// The shortcuts of one place in the app.
class KeyboardShortcutGroup {
  const KeyboardShortcutGroup({
    required this.title,
    required this.shortcuts,
    this.note,
  });

  final String title;

  /// When the group's keys apply, e.g. "打点窗口打开时".
  final String? note;
  final List<KeyboardShortcut> shortcuts;
}

/// Every keyboard shortcut in the app, grouped by where it works (D-065).
///
/// Each group mirrors the bindings it describes: the app-wide ones
/// (`GlobalSearchShortcuts`, `GlobalPlaybackShortcuts`), the lyric editor
/// (`LyricEditShortcuts`, `LyricListNavigation`, the inspector's split),
/// the timing dialogs (their `keys` strings) and fullscreen KTV
/// (`FullscreenKtvInteractionSurface`). A test pins the panel to them, so a
/// new shortcut has to be added here to pass.
///
/// [apple] picks the macOS variants: find and replace is ⌘⇧H there because
/// ⌘H hides the app, and Ctrl+Y is not bound.
List<KeyboardShortcutGroup> keyboardShortcutGroups({required bool apple}) => [
  const KeyboardShortcutGroup(
    title: '全局',
    shortcuts: [
      KeyboardShortcut('搜索工程、歌曲、歌单、歌词和操作', [commandKey, 'K']),
      KeyboardShortcut('查看快捷键', ['?'], alternative: [commandKey, '/']),
    ],
  ),
  const KeyboardShortcutGroup(
    title: '播放（任何页面）',
    note: '空格只在没有选中输入框或按钮时控制播放',
    shortcuts: [
      KeyboardShortcut('播放 / 暂停', ['空格']),
      KeyboardShortcut('下一首', [commandKey, '→']),
      KeyboardShortcut('上一首', [commandKey, '←']),
      KeyboardShortcut('快进 5 秒', ['Shift', '→']),
      KeyboardShortcut('快退 5 秒', ['Shift', '←']),
    ],
  ),
  const KeyboardShortcutGroup(
    title: '搜索框',
    shortcuts: [
      KeyboardShortcut('选择上一个 / 下一个结果', ['↑'], alternative: ['↓']),
      KeyboardShortcut('打开选中的结果（歌曲直接播放）', ['Enter']),
      KeyboardShortcut('歌曲加入播放队列 / 播放整个歌单', ['Shift', 'Enter']),
      KeyboardShortcut('关闭', ['Esc']),
    ],
  ),
  KeyboardShortcutGroup(
    title: '歌词校对',
    shortcuts: [
      const KeyboardShortcut('保存', [commandKey, 'S']),
      const KeyboardShortcut('撤销', [commandKey, 'Z']),
      KeyboardShortcut('重做', _redo, alternative: apple ? null : _ctrlY),
      KeyboardShortcut(
        '查找和替换',
        apple ? const ['⌘', 'Shift', 'H'] : const ['Ctrl', 'H'],
      ),
      const KeyboardShortcut('在歌词列表里搜索', [commandKey, 'F']),
      const KeyboardShortcut('选择上一行 / 下一行', ['↑'], alternative: ['↓']),
      const KeyboardShortcut('编辑选中的行', ['Enter'], alternative: ['F2']),
      const KeyboardShortcut(
        '删除选中的行（多选时删除选中的全部行，可撤销）',
        [commandKey, 'Delete'],
        alternative: [commandKey, '退格'],
      ),
      const KeyboardShortcut('多选：加选或取消这一行', [commandKey, '点击']),
      const KeyboardShortcut(
        '多选：连续选到这一行',
        ['Shift', '点击'],
        alternative: ['Shift', '↑/↓'],
      ),
      const KeyboardShortcut('多选：选中列表里显示的全部行', [commandKey, 'A']),
      const KeyboardShortcut('退出多选', ['Esc']),
      const KeyboardShortcut('编辑中：保存这一行', ['Enter']),
      const KeyboardShortcut('编辑中：放弃修改', ['Esc']),
      const KeyboardShortcut('右侧编辑框：在光标处拆成两行', [commandKey, 'Enter']),
    ],
  ),
  const KeyboardShortcutGroup(
    title: '逐行打轴',
    note: '打轴窗口打开时',
    shortcuts: [
      KeyboardShortcut('这一句开唱时打点', ['空格']),
      KeyboardShortcut('结束本行', ['Enter']),
      KeyboardShortcut('撤回上一个点', ['退格']),
      KeyboardShortcut('后退 3 秒', ['←']),
      KeyboardShortcut('播放 / 暂停', ['P']),
    ],
  ),
  const KeyboardShortcutGroup(
    title: '逐字打点',
    note: '逐字打点窗口打开时',
    shortcuts: [
      KeyboardShortcut('这个字开唱时打点', ['空格']),
      KeyboardShortcut('结束本字', ['Enter']),
      KeyboardShortcut('撤回上一个点', ['退格']),
      KeyboardShortcut('重打本行', ['R']),
      KeyboardShortcut('后退 3 秒', ['←']),
      KeyboardShortcut('播放 / 暂停', ['P']),
    ],
  ),
  const KeyboardShortcutGroup(
    title: '逐字微调',
    note: '微调窗口打开时；按住 Shift 每次 50 毫秒，否则 10 毫秒',
    shortcuts: [
      KeyboardShortcut('选上一个 / 下一个字', ['←'], alternative: ['→']),
      KeyboardShortcut('开始时间提前 / 推后', ['A'], alternative: ['D']),
      KeyboardShortcut('结束时间提前 / 推后', ['J'], alternative: ['L']),
      KeyboardShortcut('整个字提前 / 推后', ['Q'], alternative: ['E']),
      KeyboardShortcut('开始 / 结束设为播放位置', ['['], alternative: [']']),
      KeyboardShortcut('试听这个字', ['空格']),
      KeyboardShortcut('撤销上一步', ['退格']),
    ],
  ),
  const KeyboardShortcutGroup(
    title: '全屏 KTV',
    shortcuts: [
      KeyboardShortcut('退出全屏', ['Esc']),
      KeyboardShortcut('播放 / 暂停', ['空格']),
      KeyboardShortcut('后退 / 前进 5 秒', ['←'], alternative: ['→']),
      KeyboardShortcut(
        '上一首 / 下一首',
        [commandKey, '←'],
        alternative: [commandKey, '→'],
      ),
    ],
  ),
];
