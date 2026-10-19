import 'dart:io';

class AsrDownloadHttpClientFactory {
  final Map<String, String> Function() _environment;
  final Future<String?> Function()? _systemProxyLookup;

  AsrDownloadHttpClientFactory({
    Map<String, String> Function()? environment,
    Future<String?> Function()? systemProxyLookup,
  }) : _environment = environment ?? (() => Platform.environment),
       _systemProxyLookup = systemProxyLookup;

  Future<HttpClient> create({String? manualProxy}) async {
    final directive = await resolveProxyDirective(manualProxy: manualProxy);
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..findProxy = (_) => directive;
  }

  Future<String> resolveProxyDirective({String? manualProxy}) async {
    final override = manualProxy?.trim() ?? '';
    if (override.isNotEmpty) {
      return _proxyDirective(_parseHttpProxy(override));
    }

    final environmentDirective = HttpClient.findProxyFromEnvironment(
      Uri.https('huggingface.co', '/'),
      environment: _environment(),
    );
    if (environmentDirective.toUpperCase() != 'DIRECT') {
      return environmentDirective;
    }

    final systemProxy = _systemProxyLookup == null
        ? await _readSystemProxy()
        : await _systemProxyLookup();
    if (systemProxy == null || systemProxy.trim().isEmpty) return 'DIRECT';
    return _proxyDirective(_parseHttpProxy(systemProxy.trim()));
  }

  Future<String?> _readSystemProxy() async {
    if (Platform.isWindows) return _readWindowsSystemProxy();
    if (Platform.isMacOS) return _readMacOsSystemProxy();
    return null;
  }

  Future<String?> _readWindowsSystemProxy() async {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    final enabled = await Process.run('reg.exe', [
      'query',
      key,
      '/v',
      'ProxyEnable',
    ]).timeout(const Duration(seconds: 5));
    if (enabled.exitCode != 0) return null;

    final output = enabled.stdout.toString();
    final isEnabled = RegExp(
      r'ProxyEnable\s+REG_DWORD\s+0x1\b',
      caseSensitive: false,
    ).hasMatch(output);
    if (!isEnabled) {
      final autoConfig = await Process.run('reg.exe', [
        'query',
        key,
        '/v',
        'AutoConfigURL',
      ]).timeout(const Duration(seconds: 5));
      if (autoConfig.exitCode == 0 &&
          autoConfig.stdout.toString().contains('REG_SZ')) {
        throw const FormatException(
          '检测到 Windows 自动代理脚本（PAC）；请在高级设置中填写本机 HTTP 代理地址',
        );
      }
      return null;
    }

    final server = await Process.run('reg.exe', [
      'query',
      key,
      '/v',
      'ProxyServer',
    ]).timeout(const Duration(seconds: 5));
    if (server.exitCode != 0) {
      throw const FormatException('Windows 系统代理已启用，但未找到代理服务器地址');
    }
    final match = RegExp(
      r'ProxyServer\s+REG_SZ\s+(.+)',
      caseSensitive: false,
    ).firstMatch(server.stdout.toString());
    if (match == null || match.group(1)!.trim().isEmpty) {
      throw const FormatException('无法读取 Windows 系统代理服务器地址');
    }
    return parseWindowsProxyServer(match.group(1)!.trim());
  }

  Future<String?> _readMacOsSystemProxy() async {
    final result = await Process.run('/usr/sbin/scutil', const [
      '--proxy',
    ]).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) {
      throw FormatException('无法读取 macOS 系统代理设置：${result.stderr}');
    }

    return parseMacOsProxySettings(result.stdout.toString());
  }

  static String? parseMacOsProxySettings(String source) {
    final settings = _parseScutilSettings(source);
    if (settings['ProxyAutoConfigEnable'] == '1' ||
        settings['ProxyAutoDiscoveryEnable'] == '1') {
      throw const FormatException(
        '检测到 macOS 自动代理脚本（PAC/WPAD）；请在高级设置中填写本机 HTTP 代理地址',
      );
    }

    final https = _enabledProxy(
      settings,
      enabledKey: 'HTTPSProxyEnable',
      hostKey: 'HTTPSProxy',
      portKey: 'HTTPSPort',
    );
    if (https != null) return https;

    return _enabledProxy(
      settings,
      enabledKey: 'HTTPEnable',
      hostKey: 'HTTPProxy',
      portKey: 'HTTPPort',
    );
  }

  static Map<String, String> _parseScutilSettings(String source) {
    final settings = <String, String>{};
    for (final line in source.split(RegExp(r'[\r\n]+'))) {
      final match = RegExp(
        r'^\s*([A-Za-z0-9]+)\s*:\s*(.*?)\s*$',
      ).firstMatch(line);
      if (match != null) settings[match.group(1)!] = match.group(2)!;
    }
    return settings;
  }

  static String? _enabledProxy(
    Map<String, String> settings, {
    required String enabledKey,
    required String hostKey,
    required String portKey,
  }) {
    if (settings[enabledKey] != '1') return null;
    final host = settings[hostKey]?.trim() ?? '';
    final port = settings[portKey]?.trim() ?? '';
    if (host.isEmpty || int.tryParse(port) == null) {
      throw FormatException('系统代理 $hostKey/$portKey 配置不完整');
    }
    return 'http://$host:$port';
  }

  static String parseWindowsProxyServer(String raw) {
    final entries = <String, String>{};
    for (final entry in raw.split(';')) {
      final separator = entry.indexOf('=');
      if (separator > 0) {
        entries[entry.substring(0, separator).trim().toLowerCase()] = entry
            .substring(separator + 1)
            .trim();
      }
    }
    if (entries.containsKey('socks') &&
        !entries.containsKey('http') &&
        !entries.containsKey('https')) {
      throw const FormatException('当前系统只配置了 SOCKS 代理；请在高级设置中填写 HTTP 代理地址');
    }
    final selected = entries['https'] ?? entries['http'] ?? raw;
    if (selected.trim().isEmpty) {
      throw const FormatException('Windows 系统代理服务器地址为空；请在高级设置中填写 HTTP 代理地址');
    }
    return selected.contains('://') ? selected : 'http://$selected';
  }

  static Uri _parseHttpProxy(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'http' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        '代理地址无效。请输入不含账号密码的 HTTP 代理地址，例如 http://127.0.0.1:7890',
      );
    }
    return uri;
  }

  static String _proxyDirective(Uri uri) => 'PROXY ${uri.authority}';
}
