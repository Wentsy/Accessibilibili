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
      let wasEnabled = Self.backgroundPlaybackEnabled

      if enabled {
        // MPRemoteCommandCenter targets are installed by audio_service, but its
        // iOS fork never explicitly registers the application for remote-control
        // delivery. Active audio makes iOS infer that role while already
        // playing; a foreground-paused player has no audio output to do that for
        // us before suspension. Keep the app registered for system media events
        // for the whole lifetime of background playback instead.
        UIApplication.shared.beginReceivingRemoteControlEvents()
      } else if wasEnabled {
        applyPlaybackRole(background: false, force: true)
        UIApplication.shared.endReceivingRemoteControlEvents()
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
          guard Self.backgroundPlaybackEnabled else { return }
          UIApplication.shared.beginReceivingRemoteControlEvents()
          self.applyPlaybackRole(background: true)
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
          guard Self.backgroundPlaybackEnabled else { return }
          UIApplication.shared.beginReceivingRemoteControlEvents()
          self.applyPlaybackRole(background: true)
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

  deinit {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
