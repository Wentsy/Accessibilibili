import AVFoundation
import Flutter
import MediaPlayer
import UIKit

public class MediaKitLibsIosVideoPlugin: NSObject, FlutterPlugin {
  private static var backgroundPlaybackEnabled = false
  private var lifecycleObservers: [NSObjectProtocol] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MediaKitLibsIosVideoPlugin()
    let channel = FlutterMethodChannel(
      name: "accessibilibili/background_audio",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.installLifecycleObservers()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setBackgroundPlaybackEnabled":
      let enabled = call.arguments as? Bool ?? false
      if !enabled && Self.backgroundPlaybackEnabled {
        applyPlaybackRole(background: false, force: true)
      }
      Self.backgroundPlaybackEnabled = enabled
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installLifecycleObservers() {
    let center = NotificationCenter.default
    if #available(iOS 13.0, *) {
      lifecycleObservers.append(
        center.addObserver(
          forName: UIScene.didEnterBackgroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          guard let self else { return }
          self.applyPlaybackRole(background: true)
          self.reassertPausedNowPlayingIfNeeded()
        }
      )
      lifecycleObservers.append(
        center.addObserver(
          forName: UIScene.willEnterForegroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.applyPlaybackRole(background: false)
        }
      )
    } else {
      lifecycleObservers.append(
        center.addObserver(
          forName: UIApplication.didEnterBackgroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          guard let self else { return }
          self.applyPlaybackRole(background: true)
          self.reassertPausedNowPlayingIfNeeded()
        }
      )
      lifecycleObservers.append(
        center.addObserver(
          forName: UIApplication.willEnterForegroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.applyPlaybackRole(background: false)
        }
      )
    }
  }

  private func applyPlaybackRole(background: Bool, force: Bool = false) {
    guard force || Self.backgroundPlaybackEnabled else { return }

    let session = AVAudioSession.sharedInstance()
    let categoryOptions: AVAudioSession.CategoryOptions = background
      ? []
      : [.mixWithOthers]
    do {
      try session.setCategory(
        .playback,
        mode: .default,
        options: categoryOptions
      )
      try session.setActive(true, options: [])
    } catch {
      // Dart's audio_session path remains a fallback on the next transition.
    }
  }

  private func reassertPausedNowPlayingIfNeeded() {
    guard Self.backgroundPlaybackEnabled else { return }

    let center = MPNowPlayingInfoCenter.default()
    guard var info = center.nowPlayingInfo else { return }

    // Leave the already-working playing -> background path untouched. The
    // audio_service bridge publishes playbackRate == 0 for a paused item.
    let playbackRate =
      (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
    guard playbackRate == 0 else { return }

    // The custom audio_service also writes DefaultPlaybackRate == 0 while
    // paused. Keep current rate at zero, but restore a resumable baseline and
    // republish the same metadata after this app becomes the primary playback
    // session. This gives iOS a fresh paused Now Playing candidate to route a
    // lock-screen/Magic Tap Play command to.
    let defaultRate =
      (info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? NSNumber)?.doubleValue ?? 0
    if defaultRate <= 0 {
      info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    }
    info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    center.nowPlayingInfo = info

    // audio_service still owns the command targets; do not add duplicates.
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = true
    commands.togglePlayPauseCommand.isEnabled = true
  }

  deinit {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
