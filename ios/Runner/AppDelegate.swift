import Flutter
import ObjectiveC.runtime
import UIKit

/// VoiceOver reads focused Flutter text fields through the engine's
/// `TextInputSemanticsObject`, which implements `UITextInput` and delegates to
/// Flutter's hidden text-input view. Keep Flutter's real editing buffer and
/// selection offsets untouched, but substitute a spoken label when that
/// accessibility-only object asks for the single code unit occupied by an
/// inline emote.
private final class RichTextEmoteAccessibility {
  static let shared = RichTextEmoteAccessibility()

  private let placeholder = "☺"
  private var expectedText = ""
  private var labelsByOffset: [Int: String] = [:]
  private var isInstalled = false

  private init() {}

  func install() {
    guard !isInstalled,
          let textInputClass = NSClassFromString("TextInputSemanticsObject")
    else {
      return
    }

    let selector = NSSelectorFromString("textInRange:")
    guard let method = class_getInstanceMethod(textInputClass, selector) else {
      return
    }

    typealias OriginalTextInRange = @convention(c) (
      AnyObject,
      Selector,
      UITextRange
    ) -> NSString?

    let originalImplementation = method_getImplementation(method)
    let original = unsafeBitCast(
      originalImplementation,
      to: OriginalTextInRange.self
    )

    let replacement: @convention(block) (AnyObject, UITextRange) -> NSString? = {
      [weak self] object, range in
      let originalText = original(object, selector, range)
      guard let self else {
        return originalText
      }
      return self.accessibleText(
        for: object,
        range: range,
        originalText: originalText
      )
    }

    method_setImplementation(method, imp_implementationWithBlock(replacement))
    isInstalled = true
  }

  func update(text: String, emotes: [[String: Any]]) {
    expectedText = text

    var nextLabels: [Int: String] = [:]
    for emote in emotes {
      guard let start = emote["start"] as? Int,
            let label = emote["label"] as? String,
            !label.isEmpty
      else {
        continue
      }
      nextLabels[start] = label
    }
    labelsByOffset = nextLabels
  }

  private func accessibleText(
    for object: AnyObject,
    range: UITextRange,
    originalText: NSString?
  ) -> NSString? {
    guard UIAccessibility.isVoiceOverRunning,
          let originalText,
          originalText as String == placeholder,
          let semanticsObject = object as? NSObject,
          let currentValue = semanticsObject.value(forKey: "accessibilityValue") as? NSString,
          currentValue as String == expectedText,
          let startPosition = range.start as? NSObject,
          let endPosition = range.end as? NSObject,
          let startNumber = startPosition.value(forKey: "index") as? NSNumber,
          let endNumber = endPosition.value(forKey: "index") as? NSNumber
    else {
      return originalText
    }

    let start = startNumber.intValue
    guard endNumber.intValue == start + 1,
          let label = labelsByOffset[start]
    else {
      return originalText
    }

    return label as NSString
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var accessibilityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false // Disable shake to undo
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    RichTextEmoteAccessibility.shared.install()

    let channel = FlutterMethodChannel(
      name: "accessibilibili/accessibility",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    accessibilityChannel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pageScrolled":
        if UIAccessibility.isVoiceOverRunning {
          // pageScrolled is the UIKit-native accessibility notification for a
          // completed VoiceOver scroll gesture. An empty position string keeps
          // the native scroll cue without adding extra spoken wording.
          UIAccessibility.post(notification: .pageScrolled, argument: "")
        }
        result(nil)
      case "setRichTextEmotes":
        if let arguments = call.arguments as? [String: Any],
           let text = arguments["text"] as? String,
           let emotes = arguments["emotes"] as? [[String: Any]] {
          RichTextEmoteAccessibility.shared.update(text: text, emotes: emotes)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func accessibilityPerformMagicTap() -> Bool {
    guard let channel = accessibilityChannel else {
      return super.accessibilityPerformMagicTap()
    }

    channel.invokeMethod("magicTap", arguments: nil)
    return true
  }
}
