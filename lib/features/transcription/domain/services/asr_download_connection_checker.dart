abstract interface class AsrDownloadConnectionChecker {
  Future<void> testConnection({String? proxyOverride});
}
