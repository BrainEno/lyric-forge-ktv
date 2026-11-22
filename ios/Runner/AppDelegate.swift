import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LyricForgeMediaAudio") {
      MediaAudioExtractorChannel.register(messenger: registrar.messenger())
    }
  }
}

/// Pulls the sound track out of a video into a small AAC `.m4a` file
/// (decision D-056). Dart side: `MethodChannelMediaAudioExtractor`.
enum MediaAudioExtractorChannel {
  static let name = "io.github.braineno.lyricforge/media_audio"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "extractAudio" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let input = arguments["input"] as? String,
        let output = arguments["output"] as? String
      else {
        result(FlutterError(code: "export-failed", message: "input and output are required", details: nil))
        return
      }
      extract(input: input, output: output, result: result)
    }
  }

  private static func extract(input: String, output: String, result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    let outputURL = URL(fileURLWithPath: output)
    try? FileManager.default.removeItem(at: outputURL)

    asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
      var error: NSError?
      guard asset.statusOfValue(forKey: "tracks", error: &error) == .loaded else {
        finish(result, FlutterError(
          code: "export-failed",
          message: error?.localizedDescription ?? "无法读取这个文件",
          details: nil))
        return
      }
      guard !asset.tracks(withMediaType: .audio).isEmpty else {
        finish(result, FlutterError(code: "no-audio", message: "这个视频没有声音", details: nil))
        return
      }
      guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
        finish(result, FlutterError(code: "unsupported-codec", message: "无法读取这个视频的音轨", details: nil))
        return
      }
      session.outputURL = outputURL
      session.outputFileType = .m4a
      session.shouldOptimizeForNetworkUse = false
      session.exportAsynchronously {
        switch session.status {
        case .completed:
          let seconds = CMTimeGetSeconds(asset.duration)
          var reply: [String: Any] = ["path": output]
          if seconds.isFinite && seconds > 0 {
            reply["durationMs"] = Int(seconds * 1000)
          }
          finish(result, reply)
        case .cancelled:
          try? FileManager.default.removeItem(at: outputURL)
          finish(result, FlutterError(code: "export-failed", message: "已取消", details: nil))
        default:
          try? FileManager.default.removeItem(at: outputURL)
          finish(result, FlutterError(
            code: "export-failed",
            message: session.error?.localizedDescription ?? "导出音频失败",
            details: nil))
        }
      }
    }
  }

  private static func finish(_ result: @escaping FlutterResult, _ value: Any) {
    DispatchQueue.main.async { result(value) }
  }
}
