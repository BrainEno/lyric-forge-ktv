import 'package:flutter/foundation.dart';

/// How the interface names the folder that holds the managed speech
/// recognition environment, and the messages of the "reuse an existing
/// download" flow shared by the setup dialog and the settings page.
///
/// On disk the environment is always `LyricForge/ASRRuntime` below a parent
/// the user picked, for example `D:\Models\LyricForge\ASRRuntime` on Windows.
/// The interface used to write "LyricForge ASRRuntime" with a space, as if it
/// were a product, and "已有的 ASRRuntime" without saying where that is, so a
/// user looking at `D:\Models\LyricForge\ASRRuntime` could not tell it was
/// the folder being asked for. Every message now spells out the folder as a
/// path, with the separator of the platform, and the paste dialog shows a
/// full example.
///
/// The two flows also kept separate copies of each message; they now read
/// them from here.
class AsrFolderText {
  const AsrFolderText._();

  static bool get _windows => defaultTargetPlatform == TargetPlatform.windows;
  static bool get _macOS => defaultTargetPlatform == TargetPlatform.macOS;

  /// Path separator as the user sees it on this platform.
  static String get separator => _windows ? r'\' : '/';

  /// The managed folder relative to its parent: `LyricForge\ASRRuntime` on
  /// Windows, `LyricForge/ASRRuntime` elsewhere.
  static String get folder => 'LyricForge${separator}ASRRuntime';

  /// The parent most users pick, the `Models` folder in [example].
  static String get exampleParent {
    if (_windows) return r'D:\Models';
    if (_macOS) return '/Volumes/Data/Models';
    return '/mnt/data/Models';
  }

  /// A complete path of an existing environment, for hints.
  static String get example => '$exampleParent$separator$folder';

  /// Hint of the "paste a path" field: a drive, a parent or the folder.
  static String get pasteHint {
    if (_windows) return '例如 D:\\、$exampleParent 或 $example';
    return '例如 $exampleParent 或 $example';
  }

  /// Title of the paste dialog.
  static const String pasteTitle = '粘贴已有模型文件夹的路径';

  /// Explanation in the paste dialog.
  static String get pasteExplanation =>
      '模型放在 $folder 文件夹里，例如 $example。可以粘贴这个文件夹本身、它的上级'
      '（如 $exampleParent 或整个磁盘），也可以粘贴里面任意的模型文件夹或文件；'
      'Elysium Player 会向上或向下找到完整的环境。';

  /// Label of the browse button on the "already downloaded" card.
  static const String browseLabel = '浏览模型文件夹';

  /// Body of the "already downloaded" card.
  static String get cardMessage =>
      '先在本机查找以前下载的模型（$folder 文件夹，例如 $example）并原地使用。'
      '此步骤只识别已有文件：不复制、不删除，也不会开始下载。识别后若仍有组件缺失，'
      '下方会单独列出原因。';

  /// Status line while the card is scanning without a message of its own.
  static String get scanningFallback => '正在查找已有的 $folder 文件夹…（不会下载）';

  /// Title of the folder picker used to adopt an existing environment.
  static String get pickExistingTitle => '选择 $folder 文件夹，或它的上级文件夹/磁盘';

  /// Title of the folder picker used to move the environment.
  static String get pickNewParentTitle => '选择新的上级文件夹或磁盘（将使用其中的 $folder）';

  /// While the automatic search runs.
  static String get scanning => '正在常见磁盘位置查找已有的 $folder 文件夹…此步骤不会下载。';

  /// When the automatic search found nothing.
  static String get notFound =>
      '没有在常见位置找到已有的 $folder 文件夹。如果模型在别处（例如 $example），'
      '可以粘贴它的路径，也可以继续在当前目录校验并补齐缺失组件。';

  /// While a pasted or picked path is examined.
  static String checkingPath(String path) =>
      '正在从 $path 识别已有的 $folder 文件夹…此步骤不会下载。';

  /// When a pasted or picked path held no environment.
  static String get pathNotRecognised => '没有从该路径识别到 $folder 文件夹，当前目录未改变。';

  /// Body of the confirmation before moving the environment.
  static String moveConfirmation(String size) =>
      '当前托管环境约 $size。如果所选位置已有 $folder 文件夹，会直接识别并使用其中的'
      '模型，不复制、不删除当前目录；否则会先完整复制并核对文件数量与总大小，确认新目录'
      '完整后才切换路径并清理旧目录。操作期间不会启动识别任务。';
}
