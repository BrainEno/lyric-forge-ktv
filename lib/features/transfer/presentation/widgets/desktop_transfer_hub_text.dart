import '../../domain/models/media_hub_session.dart';

/// Sentences of the desktop transfer page, shared by the page and tests.
///
/// The page wrote them inline, and some of them called the library
/// "电脑 Library" in the middle of a Chinese sentence while the rest of the
/// app says 音乐库. They now live here in one place, under one name for each
/// thing: 电脑音乐库 for the library this computer shares, 传输服务 for the
/// service, 配对码 for the pairing link.
abstract final class DesktopTransferHubText {
  // Page.
  static const String desktopOnlyTitle = '请在电脑上开启跨设备传输';
  static const String desktopOnlyMessage =
      '传输服务只能在 Windows、macOS 或 Linux 上的 Elysium Player 里启动。'
      '手机请用“连接电脑”扫描电脑上的二维码。';
  static const String connectFromPhone = '连接电脑';
  static const String openLibraryTooltip = '打开电脑音乐库';

  // Security notice. The consent dialog keeps its wording in the page, where
  // the security contract test pins it.
  static const String securityTitle = '网络安全提示';
  static const String securityMessage =
      'Media Hub 使用证书指纹固定的 HTTPS 加密普通局域网和 Tailscale 连接。'
      '仅在你主动启动并完成扫码配对后，共享歌曲、歌词和封面才会开放给配对设备；'
      '配对设备也可以向电脑上传音频。请只与可信设备配对。';

  // Overview.
  static const String runningTitle = '电脑端已准备好配对';
  static const String stoppedTitle = '跨设备传输尚未启动';
  static const String libraryLoading = '正在读取电脑音乐库…';
  static const String serviceStarting = '正在启动传输服务…';
  static const String stoppedStatus = '电脑音乐库已读取；点击“启动传输服务”并确认网络风险后才会开放连接。';
  static const String start = '启动传输服务';
  static const String stop = '停止传输服务';
  static const String refresh = '刷新电脑音乐库';

  /// The line under the overview title.
  static String overviewStatus({
    required bool initializing,
    required bool running,
    required int trackCount,
  }) {
    if (initializing) return libraryLoading;
    if (!running) return stoppedStatus;
    if (trackCount <= 0) {
      return '二维码就在下方。电脑音乐库里还没有歌曲，手机连上后可以先向电脑发送音乐。';
    }
    return '二维码就在下方。当前自动共享 $trackCount 首电脑音乐库里的歌曲。';
  }

  // Pairing.
  static const String scanStep = '1. 用手机扫描这个二维码';
  static const String scanHint = '手机端：跨设备传输 → 连接电脑 → 扫描桌面二维码。';
  static const String copyStep = '2. 或复制下面的配对码';
  static const String copy = '复制配对码';
  static const String copied = '配对码已复制，可以粘贴到手机端。';
  static const String endpointsTitle = '可连接地址';
  static const String waitingMessage = '传输服务默认关闭；确认网络风险后才会显示配对二维码';
  static const String startAndPair = '启动并生成二维码';

  /// Name of the network an address is on. The page showed the raw enum
  /// names ("lan", "tailscale", "other").
  static String endpointKind(MediaHubEndpointKind kind) => switch (kind) {
    MediaHubEndpointKind.lan => '局域网',
    MediaHubEndpointKind.tailscale => 'Tailscale（可远程连接）',
    MediaHubEndpointKind.other => '其他网络',
  };

  /// One line of the address list.
  static String endpoint(MediaHubEndpoint endpoint) =>
      '${endpointKind(endpoint.kind)}：${endpoint.host}:${endpoint.port}';

  // Directions.
  static const String toPhoneTitle = '电脑 → 手机';
  static const String toPhoneStopped = '启动服务后，电脑音乐库会自动作为手机可下载列表。';
  static const String toComputerTitle = '手机 → 电脑';
  static const String toComputerStopped = '启动服务后，手机即可把本地音乐批量发送到这台电脑。';

  /// The folder under the user's documents where songs sent from a phone
  /// are saved. It is a real directory name (D-030), so it stays as is.
  static const String incomingFolder = 'LyricForge/Incoming';

  static String toPhoneRunning(int trackCount) =>
      '电脑音乐库里的 $trackCount 首可用歌曲已经自动共享。'
      '手机扫码后可以在线播放，或选择“下载并播放”，下载完成后会进入手机本地音乐库。';

  static const String toComputerRunning =
      '手机连接后可多选本机音频发送到电脑。文件完整传完后会保存到文稿文件夹下的'
      ' $incomingFolder，并自动加入电脑音乐库；点右上角音乐库按钮即可直接播放。';

  // Shared tracks.
  static const String tracksCaption = '这里直接来自电脑音乐库，不需要再重复选择文件。';
  static const String reachable = '手机可访问';
  static const String stopped = '服务已停止';
  static const String tracksEmptyTitle = '电脑音乐库里还没有歌曲';
  static const String tracksEmptyMessage = '先把歌曲导入音乐库，再点“刷新电脑音乐库”，手机就能看到它们。';
  static const String openLibrary = '打开音乐库';

  /// Most rows the page previews; the phone sees the full list.
  static const int previewLimit = 12;

  static String tracksTitle(int count) => '电脑共享音乐 · $count 首';

  static String moreTracks(int hidden) => '另有 $hidden 首未在此预览；手机端会看到完整列表。';

  // Results.
  static const String failureTitle = '跨设备传输暂时不可用';
  static const String refreshedRunning = '电脑音乐库已刷新；二维码已更新，请让手机重新扫码。';
  static const String refreshedStopped = '电脑音乐库已刷新；传输服务仍保持关闭。';
  static String readFailed(Object error) => '读取电脑音乐库失败：$error';
  static String refreshFailed(Object error) => '刷新共享音乐库失败：$error';
  static String startFailed(Object error) => '启动传输服务失败：$error';
  static String stopFailed(Object error) => '停止传输服务失败：$error';

  /// Size of a shared file. Under 1 KB it used to read "0 KB".
  static String fileSize(int bytes) {
    const kib = 1024;
    const mib = 1024 * 1024;
    if (bytes < kib) return '$bytes B';
    if (bytes < mib) return '${(bytes / kib).toStringAsFixed(0)} KB';
    return '${(bytes / mib).toStringAsFixed(1)} MB';
  }
}
