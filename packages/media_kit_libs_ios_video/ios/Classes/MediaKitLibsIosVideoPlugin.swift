import AVFoundation
import Flutter
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
        // If the preference is turned off after a previous background session,
        // immediately return to the VoiceOver-friendly foreground role before
        // clearing the flag that guards normal lifecycle transitions.
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
          self?.applyPlaybackRole(background: true)
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
          self?.applyPlaybackRole(background: true)
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
      // Flutter lifecycle callbacks are asynchronous and a paused player has no
      // active AudioUnit keeping the process alive. Perform this tiny category
      // switch synchronously from UIKit's scene lifecycle instead: background
      // becomes the primary Now Playing app, foreground remains mixable so
      // VoiceOver speech is not cut off by video audio.
      try session.setCategory(
        .playback,
        mode: .default,
        options: categoryOptions
      )
      try session.setActive(true, options: [])
    } catch {
      // Dart's audio_session path remains as a fallback on the next lifecycle
      // or playback transition; a transient AVAudioSession refusal is harmless.
    }
  }

  deinit {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
