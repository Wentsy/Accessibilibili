import AVFoundation
import Flutter
import Photos
import UIKit

/// File operations only: never activate or reconfigure the playback audio session.
final class VideoPhotoExporter {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "accessibilibili/video_export", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          DispatchQueue.main.async { result(status == .authorized || status == .limited) }
        }
      case "prepareMovie":
        guard let args = call.arguments as? [String: Any],
              let videos = args["videos"] as? [String], !videos.isEmpty else {
          result(FlutterError(code: "arguments", message: "沒有可匯出的影片", details: nil))
          return
        }
        let audio = args["audio"] as? String
        let expected = (args["durationMs"] as? NSNumber)?.doubleValue ?? 0
        DispatchQueue.global(qos: .userInitiated).async {
          prepareMovie(videos: videos, audio: audio, expected: expected / 1000, result: result)
        }
      case "saveMovie":
        guard let path = call.arguments as? String,
              FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "missing", message: "匯出檔案不存在", details: nil))
          return
        }
        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path) else {
          result(FlutterError(code: "format", message: "照片圖庫不支援這個影片格式，請改用 H.264 重新下載", details: nil))
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: path))
        }) { success, error in
          DispatchQueue.main.async {
            if success { result(nil) }
            else {
              result(FlutterError(code: "photos", message: error?.localizedDescription ?? "照片圖庫無法保存這個影片格式", details: nil))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private func exportError(_ message: String) -> NSError {
  NSError(domain: "Accessibilibili.VideoExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

private func prepareMovie(videos: [String], audio: String?, expected: Double, result: @escaping FlutterResult) {
  let fm = FileManager.default
  let staging = fm.temporaryDirectory.appendingPathComponent("video-export-\(UUID().uuidString)", isDirectory: true)
  let output = fm.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString).mp4")
  func finish(_ value: Any?) {
    try? fm.removeItem(at: staging)
    DispatchQueue.main.async { result(value) }
  }
  do {
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    // .m4s is a transport filename, not a format hint AVURLAsset reliably accepts.
    // Hard links also keep a stable input if the original cache is later removed.
    func asset(_ path: String, name: String) throws -> AVURLAsset {
      let source = URL(fileURLWithPath: path)
      let target = staging.appendingPathComponent(name)
      do { try fm.linkItem(at: source, to: target) }
      catch { try fm.copyItem(at: source, to: target) }
      return AVURLAsset(url: target)
    }
    let composition = AVMutableComposition()
    guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw exportError("無法建立影片軌道")
    }
    var cursor = CMTime.zero
    var embeddedAudio: AVMutableCompositionTrack?
    for (index, path) in videos.enumerated() {
      let source = try asset(path, name: "video-\(index).mp4")
      guard !source.hasProtectedContent,
            let track = source.tracks(withMediaType: .video).first else {
        throw exportError("iPhone 無法匯出這個影片編碼，請改用 H.264 畫質重新下載")
      }
      let duration = source.duration
      guard duration.seconds.isFinite, duration.seconds > 0 else {
        throw exportError("影片檔案不完整，請重新下載")
      }
      let range = CMTimeRange(start: .zero, duration: duration)
      try videoTrack.insertTimeRange(range, of: track, at: cursor)
      if index == 0 { videoTrack.preferredTransform = track.preferredTransform }
      if audio == nil, let sound = source.tracks(withMediaType: .audio).first {
        if embeddedAudio == nil {
          embeddedAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        guard let embeddedAudio else { throw exportError("無法建立聲音軌道") }
        try embeddedAudio.insertTimeRange(range, of: sound, at: cursor)
      }
      cursor = CMTimeAdd(cursor, duration)
    }
    // Reject old caches containing only the first segment, instead of reporting success.
    if expected > 0 && cursor.seconds + max(2, expected * 0.01) < expected {
      throw exportError("快取長度不足，可能是舊版只下載了第一段；請刪除快取後重新下載")
    }
    if let audio {
      let source = try asset(audio, name: "audio.m4a")
      guard let sound = source.tracks(withMediaType: .audio).first,
            let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw exportError("聲音檔案不完整或編碼不支援，請重新下載")
      }
      guard source.duration.seconds.isFinite,
            source.duration.seconds + max(2, cursor.seconds * 0.01) >= cursor.seconds else {
        throw exportError("聲音尚未下載完整，請重新下載")
      }
      try target.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(cursor, source.duration)), of: sound, at: .zero)
    }
    exportComposition(composition, output: output, presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]) { error in
      if let error {
        try? fm.removeItem(at: output)
        finish(FlutterError(code: "export", message: error.localizedDescription, details: nil))
      } else {
        finish(output.path)
      }
    }
  } catch {
    try? fm.removeItem(at: output)
    finish(FlutterError(code: "export", message: error.localizedDescription, details: nil))
  }
}

private func exportComposition(_ composition: AVComposition, output: URL, presets: [String], completion: @escaping (Error?) -> Void) {
  guard let preset = presets.first else {
    completion(exportError("iPhone 無法合成這個影片格式，請改用 H.264 重新下載"))
    return
  }
  guard let session = AVAssetExportSession(asset: composition, presetName: preset),
        session.supportedFileTypes.contains(.mp4) else {
    exportComposition(composition, output: output, presets: Array(presets.dropFirst()), completion: completion)
    return
  }
  try? FileManager.default.removeItem(at: output)
  session.outputURL = output
  session.outputFileType = .mp4
  session.shouldOptimizeForNetworkUse = true
  session.exportAsynchronously {
    if session.status == .completed { completion(nil) }
    else if presets.count > 1 {
      exportComposition(composition, output: output, presets: Array(presets.dropFirst()), completion: completion)
    } else {
      completion(session.error ?? exportError("影片合成失敗"))
    }
  }
}
