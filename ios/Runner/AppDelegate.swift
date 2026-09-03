import Flutter
import ObjectiveC.runtime
import UIKit

/// A native rich-text mirror used only as the UITextView that VoiceOver asks
/// Flutter's text-input semantics object to expose. The real Flutter editing
/// buffer stays untouched: every image emote is still exactly one U+FFFC code
/// unit, so cursor and selection offsets remain one-to-one.
private final class RichTextAccessibilityMirror: UITextView, UITextViewDelegate {
  weak var realTextInputView: UIView?
  private var isSyncingSelection = false

  init() {
    super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
    delegate = self
    isEditable = true
    isSelectable = true
    isScrollEnabled = false
    backgroundColor = .clear
    isAccessibilityElement = false
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(text: String, labelsByOffset: [Int: String]) {
    let mutableText = NSMutableAttributedString(string: text)
    let nsText = text as NSString

    for (start, label) in labelsByOffset {
      guard start >= 0, start < nsText.length else {
        continue
      }

      let range = NSRange(location: start, length: 1)
      guard nsText.substring(with: range) == "\u{FFFC}" else {
        continue
      }

      // This is the important difference from FlutterTextInputView: a real
      // UITextView has an NSTextStorage containing a real NSTextAttachment.
      // VoiceOver's Character rotor can therefore read the attachment label in
      // the same native shape used by editors such as WeChat.
      let attachment = NSTextAttachment()
      attachment.accessibilityLabel = label
      mutableText.addAttribute(.attachment, value: attachment, range: range)
    }

    let oldSelection = selectedRange
    isSyncingSelection = true
    attributedText = mutableText

    let textLength = nsText.length
    let location = min(max(oldSelection.location, 0), textLength)
    let length = min(max(oldSelection.length, 0), textLength - location)
    selectedRange = NSRange(location: location, length: length)
    isSyncingSelection = false
  }

  func bind(to realView: UIView) {
    realTextInputView = realView
    syncSelectionFromRealTextInput()
  }

  private func syncSelectionFromRealTextInput() {
    guard let realInput = realTextInputView as? UITextInput,
          let realSelection = realInput.selectedTextRange
    else {
      return
    }

    let start = realInput.offset(
      from: realInput.beginningOfDocument,
      to: realSelection.start
    )
    let end = realInput.offset(
      from: realInput.beginningOfDocument,
      to: realSelection.end
    )
    guard start >= 0, end >= start else {
      return
    }

    let textLength = (text as NSString).length
    let location = min(start, textLength)
    let length = min(end - start, textLength - location)
    let nextSelection = NSRange(location: location, length: length)
    guard selectedRange != nextSelection else {
      return
    }

    isSyncingSelection = true
    selectedRange = nextSelection
    isSyncingSelection = false
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    guard !isSyncingSelection,
          let realInput = realTextInputView as? UITextInput
    else {
      return
    }

    let selection = selectedRange
    guard let start = realInput.position(
            from: realInput.beginningOfDocument,
            offset: selection.location
          ),
          let end = realInput.position(
            from: start,
            offset: selection.length
          ),
          let range = realInput.textRange(from: start, to: end)
    else {
      return
    }

    // FlutterTextInputView.setSelectedTextRange reports this change back to the
    // framework. Since both strings use one UTF-16 unit per emote, no offset
    // translation is needed.
    realInput.selectedTextRange = range
  }
}

private final class RichTextEmoteAccessibility {
  static let shared = RichTextEmoteAccessibility()

  private var expectedText = ""
  private var labelsByOffset: [Int: String] = [:]
  private var isInstalled = false
  private let mirror = RichTextAccessibilityMirror()

  private init() {}

  func install() {
    guard !isInstalled,
          let semanticsClass = NSClassFromString("TextInputSemanticsObject")
    else {
      return
    }

    let selector = NSSelectorFromString("textInputView")
    guard let method = class_getInstanceMethod(semanticsClass, selector) else {
      return
    }

    typealias OriginalTextInputView = @convention(c) (
      AnyObject,
      Selector
    ) -> UIView?

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: OriginalTextInputView.self
    )

    let replacement: @convention(block) (AnyObject) -> UIView? = {
      [weak self] object in
      let originalView = original(object, selector)
      guard let self,
            UIAccessibility.isVoiceOverRunning,
            !self.labelsByOffset.isEmpty,
            let originalView,
            let flutterTextInputClass = NSClassFromString("FlutterTextInputView"),
            originalView.isKind(of: flutterTextInputClass),
            let realInput = originalView as? UITextInput,
            self.fullText(of: realInput) == self.expectedText
      else {
        return originalView
      }

      self.mirror.update(
        text: self.expectedText,
        labelsByOffset: self.labelsByOffset
      )
      self.mirror.bind(to: originalView)
      return self.mirror
    }

    method_setImplementation(
      method,
      imp_implementationWithBlock(replacement)
    )
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

    mirror.update(text: text, labelsByOffset: nextLabels)
  }

  private func fullText(of input: UITextInput) -> String? {
    guard let range = input.textRange(
      from: input.beginningOfDocument,
      to: input.endOfDocument
    ) else {
      return nil
    }
    return input.text(in: range)
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
