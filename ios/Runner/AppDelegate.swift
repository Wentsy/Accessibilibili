import Flutter
import ObjectiveC.runtime
import UIKit

/// VoiceOver can reach a focused Flutter text field through either the
/// semantics proxy or the engine's hidden FlutterTextInputView. Keep the real
/// editing buffer and selection offsets untouched, and only substitute the
/// spoken string returned for a one-code-unit inline-emote placeholder.
private final class RichTextEmoteAccessibility {
  static let shared = RichTextEmoteAccessibility()

  private let placeholder = "☺"
  private var expectedText = ""
  private var labelsByOffset: [Int: String] = [:]
  private var installedClasses = Set<String>()

  private init() {}

  func install() {
    install(onClassNamed: "FlutterTextInputView")
    install(onClassNamed: "TextInputSemanticsObject")
  }

  private func install(onClassNamed className: String) {
    guard !installedClasses.contains(className),
          let textInputClass = NSClassFromString(className)
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
        className: className,
        range: range,
        originalText: originalText
      )
    }

    method_setImplementation(method, imp_implementationWithBlock(replacement))
    installedClasses.insert(className)
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
    className: String,
    range: UITextRange,
    originalText: NSString?
  ) -> NSString? {
    guard UIAccessibility.isVoiceOverRunning,
          let originalText,
          originalText as String == placeholder,
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

    // Avoid leaking a stale side table into some unrelated Flutter text field.
    // The two engine classes expose the current field text through different
    // properties, so validate using the appropriate one before substituting.
    guard let object = object as? NSObject else {
      return originalText
    }
    if className == "FlutterTextInputView" {
      guard let currentText = object.value(forKey: "text") as? NSString,
            currentText as String == expectedText
      else {
        return originalText
      }
    } else if className == "TextInputSemanticsObject" {
      guard let currentValue = object.value(forKey: "accessibilityValue") as? NSString,
            currentValue as String == expectedText
      else {
        return originalText
      }
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
        // Retry whenever metadata arrives because Flutter's engine classes can
        // be registered after AppDelegate initialization in some configurations.
        RichTextEmoteAccessibility.shared.install()
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
