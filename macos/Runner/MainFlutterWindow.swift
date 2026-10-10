import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var activeSecurityScopedURL: URL?
  private var activeSecurityScopeStarted = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerAsrSecurityScopedStorageChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  private func registerAsrSecurityScopedStorageChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: "lyric_forge/asr_security_scoped_storage",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "window_unavailable",
          message: "macOS storage authorization window is unavailable",
          details: nil
        ))
        return
      }

      switch call.method {
      case "createAndStartBookmark":
        guard
          let arguments = call.arguments as? [String: Any],
          let rawPath = arguments["path"] as? String,
          !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          result(FlutterError(
            code: "invalid_path",
            message: "A model storage folder is required",
            details: nil
          ))
          return
        }
        self.createAndStartBookmark(path: rawPath, result: result)

      case "restoreAndStartBookmark":
        guard
          let arguments = call.arguments as? [String: Any],
          let encoded = arguments["bookmark"] as? String,
          let data = Data(base64Encoded: encoded)
        else {
          result(FlutterError(
            code: "invalid_bookmark",
            message: "The saved model storage bookmark is invalid",
            details: nil
          ))
          return
        }
        self.restoreAndStartBookmark(data: data, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func createAndStartBookmark(
    path: String,
    result: @escaping FlutterResult
  ) {
    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      activateSecurityScopedURL(url)
      result([
        "path": url.path,
        "bookmark": bookmark.base64EncodedString(),
      ])
    } catch {
      result(FlutterError(
        code: "bookmark_creation_failed",
        message: "无法保存模型目录的 macOS 持久访问授权",
        details: error.localizedDescription
      ))
    }
  }

  private func restoreAndStartBookmark(
    data: Data,
    result: @escaping FlutterResult
  ) {
    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      ).standardizedFileURL

      activateSecurityScopedURL(url)
      let bookmark: Data
      if stale {
        bookmark = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      } else {
        bookmark = data
      }

      result([
        "path": url.path,
        "bookmark": bookmark.base64EncodedString(),
      ])
    } catch {
      result(FlutterError(
        code: "bookmark_restore_failed",
        message: "无法恢复模型目录的 macOS 持久访问授权，请重新选择模型存储位置",
        details: error.localizedDescription
      ))
    }
  }

  private func activateSecurityScopedURL(_ url: URL) {
    if let current = activeSecurityScopedURL,
       current.standardizedFileURL == url.standardizedFileURL {
      return
    }

    if activeSecurityScopeStarted, let current = activeSecurityScopedURL {
      current.stopAccessingSecurityScopedResource()
    }

    activeSecurityScopedURL = url
    activeSecurityScopeStarted = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if activeSecurityScopeStarted, let current = activeSecurityScopedURL {
      current.stopAccessingSecurityScopedResource()
    }
  }
}
