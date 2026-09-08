import AVFoundation
import Flutter
import MediaPlayer
import UIKit

public class MediaKitLibsIosVideoPlugin: NSObject, FlutterPlugin {
  private static var backgroundPlaybackEnabled = false
  private var lifecycleObservers: [NSObjectProtocol] = []

  // audio_service forwards remote Play back to Dart. When media is already
  // paused before the app backgrounds, iOS can suspend the Flutter engine
  // because mpv no longer has an active AudioUnit. Keep a zero-volume native
  // render graph alive only for that paused-first path so Magic Tap can wake
  // Dart and resume the real player.
  private var pausedKeepAliveEngine: AVAudioEngine?
  private var pausedKeepAlivePlayer: AVAudioPlayerNode?
  private var pausedKeepAliveBuffer: AVAudioPCMBuffer?
  private var pausedKeepAliveMonitor: Timer?

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
        // MPRemoteCommandCenter doesn't require this on modern iOS, but retain
        // responder-chain registration for accessory-event compatibility.
        UIApplication.shared.beginReceivingRemoteControlEvents()
      } else if wasEnabled {
        stopPausedKeepAlive()
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
          self.startPausedKeepAliveIfNeeded()
        }
      )
      lifecycleObservers.append(
        center.addObserver(
          forName: UIScene.willEnterForegroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          guard let self else { return }
          self.stopPausedKeepAlive()
          self.applyPlaybackRole(background: false)
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
          self.startPausedKeepAliveIfNeeded()
        }
      )
      lifecycleObservers.append(
        center.addObserver(
          forName: UIApplication.willEnterForegroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          guard let self else { return }
          self.stopPausedKeepAlive()
          self.applyPlaybackRole(background: false)
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

  private func startPausedKeepAliveIfNeeded() {
    guard Self.backgroundPlaybackEnabled else { return }
    guard pausedKeepAliveEngine == nil else { return }

    let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    guard let nowPlayingInfo = nowPlayingCenter.nowPlayingInfo else { return }

    if #available(iOS 13.0, *) {
      // Preserve the already-working playing -> background path unchanged.
      guard nowPlayingCenter.playbackState == .paused else { return }
    } else {
      let rate =
        (nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
      guard rate == 0 else { return }
    }

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true, options: [])

      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()
      engine.attach(player)

      guard let format = AVAudioFormat(
        standardFormatWithSampleRate: 8_000,
        channels: 1
      ) else {
        engine.detach(player)
        return
      }

      engine.connect(player, to: engine.mainMixerNode, format: format)
      player.volume = 0

      let frameCount = AVAudioFrameCount(format.sampleRate)
      guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: frameCount
      ) else {
        engine.detach(player)
        return
      }
      buffer.frameLength = frameCount
      if let channelData = buffer.floatChannelData {
        for channel in 0..<Int(format.channelCount) {
          for frame in 0..<Int(frameCount) {
            channelData[channel][frame] = 0
          }
        }
      }

      player.scheduleBuffer(buffer, at: nil, options: .loops)
      engine.prepare()
      try engine.start()
      player.play()

      pausedKeepAliveEngine = engine
      pausedKeepAlivePlayer = player
      pausedKeepAliveBuffer = buffer

      // When Magic Tap reaches Flutter and the real player becomes active,
      // remove the bridge immediately. This timer exists only while paused-first
      // background playback needs the bridge.
      pausedKeepAliveMonitor = Timer.scheduledTimer(
        withTimeInterval: 0.25,
        repeats: true
      ) { [weak self] _ in
        guard let self else { return }
        if #available(iOS 13.0, *),
           MPNowPlayingInfoCenter.default().playbackState == .playing {
          self.stopPausedKeepAlive()
        }
      }
    } catch {
      stopPausedKeepAlive()
    }
  }

  private func stopPausedKeepAlive() {
    pausedKeepAliveMonitor?.invalidate()
    pausedKeepAliveMonitor = nil

    pausedKeepAlivePlayer?.stop()
    pausedKeepAliveEngine?.stop()
    pausedKeepAliveEngine?.reset()

    pausedKeepAliveBuffer = nil
    pausedKeepAlivePlayer = nil
    pausedKeepAliveEngine = nil
  }

  deinit {
    stopPausedKeepAlive()
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
