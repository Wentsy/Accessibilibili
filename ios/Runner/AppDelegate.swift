import Flutter
import ObjectiveC.runtime
import UIKit

/// Adds accessibility metadata to the one-character placeholders used by rich
/// text image emotes. The editing buffer, UITextInput text and selection ranges
/// are never rewritten: VoiceOver receives the same UTF-16 string plus a named
/// accessibility attachment on each U+FFFC emote position.
private final class RichTextEmoteAccessibility {
  static let shared = RichTextEmoteAccessibility()

  private let placeholder = "\u{FFFC}"
  private let attachmentAttribute = NSAttributedString.Key(
    "NSAccessibilityAttachmentTextAttribute"
  )
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

    let selector = NSSelectorFromString("accessibilityAttributedValue")
    guard let method = class_getInstanceMethod(textInputClass, selector) else {
      return
    }

    typealias OriginalAttributedValue = @convention(c) (
      AnyObject,
      Selector
    ) -> NSAttributedString?

    let originalImplementation = method_getImplementation(method)
    let original = unsafeBitCast(
      originalImplementation,
      to: OriginalAttributedValue.self
    )

    let replacement: @convention(block) (AnyObject) -> NSAttributedString? = {
      [weak self] object in
      let originalValue = original(object, selector)
      guard let self else {
        return originalValue
      }
      return self.accessibleAttributedValue(originalValue)
    }

    let replacementImplementation = imp_implementationWithBlock(replacement)

    // accessibilityAttributedValue is inherited from SemanticsObject in the
    // Flutter engine version used by this project. Add an override only to
    // TextInputSemanticsObject so unrelated semantics nodes are untouched.
    guard class_addMethod(
      textInputClass,
      selector,
      replacementImplementation,
      method_getTypeEncoding(method)
    ) else {
      imp_removeBlock(replacementImplementation)
      return
    }

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

  private func accessibleAttributedValue(
    _ originalValue: NSAttributedString?
  ) -> NSAttributedString? {
    guard UIAccessibility.isVoiceOverRunning,
          let originalValue,
          !labelsByOffset.isEmpty,
          originalValue.string == expectedText
    else {
      return originalValue
    }

    let mutableValue = NSMutableAttributedString(attributedString: originalValue)
    let text = mutableValue.string as NSString

    for (start, label) in labelsByOffset {
      guard start >= 0, start < text.length else {
        continue
      }

      let range = NSRange(location: start, length: 1)
      guard text.substring(with: range) == placeholder else {
        continue
      }

      // Match the native attachment model used by rich text editors such as
      // WeChat, but keep our own reliable Flutter selection model. The label is
      // only the concise emote name (for example "doge"); VoiceOver supplies
      // the attachment role itself, so we deliberately do not append "表情".
      let attachment = NSTextAttachment()
      attachment.accessibilityLabel = label
      mutableValue.addAttribute(
        attachmentAttribute,
        value: attachment,
        range: range
      )
    }

    return mutableValue
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
        // Retry whenever metadata arrives because Flutter's private semantics
        // class can be registered after AppDelegate initialization.
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
