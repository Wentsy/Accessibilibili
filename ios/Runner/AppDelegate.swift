import Flutter
import ObjectiveC.runtime
import UIKit

/// Gives inline rich-text emotes the same native attachment shape that iOS
/// text editors expose to VoiceOver, without changing Flutter's editing buffer
/// or selection offsets. Each emote remains one U+FFFC code unit.
private final class RichTextEmoteAccessibility {
  static let shared = RichTextEmoteAccessibility()

  private let placeholder = "\u{FFFC}"
  private let legacyAccessibilityAttachmentAttribute = NSAttributedString.Key(
    "NSAccessibilityAttachmentTextAttribute"
  )
  private var expectedText = ""
  private var labelsByOffset: [Int: String] = [:]
  private var semanticsAttributedValueInstalled = false
  private var textInputAttributedTextInstalled = false

  private init() {}

  func install() {
    installSemanticsAttributedValue()
    installTextInputAttributedText()
  }

  /// Keep whole-field and insertion-point speech on the native attachment
  /// model. This intentionally lets attachments behave like pauses in normal
  /// editing speech, matching UIKit rich-text editors.
  private func installSemanticsAttributedValue() {
    guard !semanticsAttributedValueInstalled,
          let semanticsClass = NSClassFromString("TextInputSemanticsObject")
    else {
      return
    }

    let selector = NSSelectorFromString("accessibilityAttributedValue")
    guard let method = class_getInstanceMethod(semanticsClass, selector) else {
      return
    }

    typealias OriginalAttributedValue = @convention(c) (
      AnyObject,
      Selector
    ) -> NSAttributedString?

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: OriginalAttributedValue.self
    )

    let replacement: @convention(block) (AnyObject) -> NSAttributedString? = {
      [weak self] object in
      let originalValue = original(object, selector)
      guard let self else {
        return originalValue
      }
      return self.namedAttributedString(from: originalValue)
    }

    let replacementImplementation = imp_implementationWithBlock(replacement)

    // Flutter 3.47 inherits this method from SemanticsObject. Add an override
    // only to text-input semantics so unrelated controls are untouched.
    guard class_addMethod(
      semanticsClass,
      selector,
      replacementImplementation,
      method_getTypeEncoding(method)
    ) else {
      imp_removeBlock(replacementImplementation)
      return
    }

    semanticsAttributedValueInstalled = true
  }

  /// Native UITextView stores real NSTextAttachment objects in attributedText.
  /// WeChat's editor follows that model, which lets VoiceOver's Character rotor
  /// read an attachment's accessibilityLabel. FlutterTextInputView normally has
  /// only a plain NSMutableString, so expose a read-only attributedText getter
  /// with named attachments while leaving its real `text` and UITextInput
  /// selection model unchanged.
  private func installTextInputAttributedText() {
    guard !textInputAttributedTextInstalled,
          let textInputClass = NSClassFromString("FlutterTextInputView")
    else {
      return
    }

    let selector = NSSelectorFromString("attributedText")
    guard let prototypeMethod = class_getInstanceMethod(UITextView.self, selector) else {
      return
    }

    let replacement: @convention(block) (AnyObject) -> NSAttributedString? = {
      [weak self] object in
      guard let self,
            let object = object as? NSObject,
            let currentText = object.value(forKey: "text") as? NSString
      else {
        return nil
      }

      let plainText = currentText as String
      guard UIAccessibility.isVoiceOverRunning,
            plainText == self.expectedText,
            !self.labelsByOffset.isEmpty
      else {
        return NSAttributedString(string: plainText)
      }

      return self.namedAttributedString(from: NSAttributedString(string: plainText))
    }

    let replacementImplementation = imp_implementationWithBlock(replacement)
    let typeEncoding = method_getTypeEncoding(prototypeMethod)

    if class_addMethod(
      textInputClass,
      selector,
      replacementImplementation,
      typeEncoding
    ) {
      textInputAttributedTextInstalled = true
      return
    }

    // Be defensive in case a future Flutter engine adds attributedText itself.
    // In that case replace only FlutterTextInputView's implementation.
    guard let existingMethod = class_getInstanceMethod(textInputClass, selector) else {
      imp_removeBlock(replacementImplementation)
      return
    }
    method_setImplementation(existingMethod, replacementImplementation)
    textInputAttributedTextInstalled = true
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

  private func namedAttributedString(
    from originalValue: NSAttributedString?
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

      let attachment = NSTextAttachment()
      attachment.accessibilityLabel = label

      // Standard UIKit attachment metadata is what native rich-text editors
      // expose. Keep the legacy accessibility attachment key as a compatibility
      // hint for VoiceOver versions that still consult it.
      mutableValue.addAttribute(.attachment, value: attachment, range: range)
      mutableValue.addAttribute(
        legacyAccessibilityAttachmentAttribute,
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
        // Retry whenever metadata arrives because Flutter's private engine
        // classes can be registered after AppDelegate initialization.
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
