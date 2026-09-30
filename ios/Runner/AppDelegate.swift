import Flutter
import UIKit

/// UITextView receives VoiceOver double-tap through accessibilityActivate(),
/// not through the ordinary tap gesture recognizer. While the emoji/more panel
/// is open the editor is intentionally read-only, so forward that activation
/// back to Flutter to switch to the keyboard before normal editing resumes.
private final class IOSAccessibleRichTextView: UITextView {
  var onReadOnlyAccessibilityActivate: (() -> Void)?
  var onEditableAccessibilityActivate: (() -> Bool)?

  override func accessibilityActivate() -> Bool {
    if !isEditable {
      onReadOnlyAccessibilityActivate?()
      return true
    }
    if onEditableAccessibilityActivate?() == true {
      return true
    }
    return super.accessibilityActivate()
  }

  override func deleteBackward() {
    var deletedAttachmentLabel: String?
    let selection = selectedRange

    if selection.length == 0 && selection.location > 0 {
      let attachmentIndex = selection.location - 1
      if attachmentIndex < textStorage.length,
         let attachment = textStorage.attribute(
           .attachment,
           at: attachmentIndex,
           effectiveRange: nil
         ) as? NSTextAttachment,
         let label = attachment.accessibilityLabel,
         !label.isEmpty {
        deletedAttachmentLabel = label
      }
    }

    // Keep the real edit path completely native. This still produces the same
    // one-character deletion delta that Dart uses to remove the RichTextItem.
    super.deleteBackward()

    // VoiceOver has no stable character-deletion feedback for NSTextAttachment:
    // it may read unrelated editor text or keyboard predictions. Only normalize
    // this one case; ordinary character deletion keeps the user's own feedback
    // settings untouched.
    guard UIAccessibility.isVoiceOverRunning,
          let deletedAttachmentLabel
    else {
      return
    }

    let announcement = NSAttributedString(
      string: "刪除 \(deletedAttachmentLabel)",
      attributes: [.accessibilitySpeechQueueAnnouncement: false]
    )
    DispatchQueue.main.async {
      UIAccessibility.post(notification: .announcement, argument: announcement)
    }
  }
}

/// VoiceOver may focus an NSTextAttachment as the active accessibility element
/// instead of the surrounding UITextView. Forward the double-tap from that
/// attachment back to the editor so named emotes do not block boundary jumps.
private final class IOSAccessibleTextAttachment: NSTextAttachment {
  var onAccessibilityActivate: (() -> Bool)?

  override func accessibilityActivate() -> Bool {
    onAccessibilityActivate?() ?? false
  }
}

private final class IOSRichTextEditorFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    IOSRichTextEditor(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class IOSRichTextEditor: NSObject, FlutterPlatformView, UITextViewDelegate {
  private static let imageCache = NSCache<NSString, UIImage>()

  private let textView: IOSAccessibleRichTextView
  private let placeholderLabel = UILabel()
  private let channel: FlutterMethodChannel

  private var applyingFlutterState = false
  private var readOnly = false
  private var wantsFocusAfterReadOnlyActivation = false
  private var lastContentSignature = ""
  private var lastReportedHeight: CGFloat = 0
  private var imageTasks: [URLSessionDataTask] = []

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    textView = IOSAccessibleRichTextView(frame: frame)
    channel = FlutterMethodChannel(
      name: "accessibilibili/rich_text_editor/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    configureTextView()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      self.handle(call: call, result: result)
    }

    if let args = arguments as? [String: Any] {
      applyState(args)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    imageTasks.forEach { $0.cancel() }
  }

  func view() -> UIView {
    textView
  }

  private func configureTextView() {
    textView.delegate = self
    textView.backgroundColor = .clear
    textView.isOpaque = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = false
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.font = UIFont.preferredFont(forTextStyle: .body)
    textView.textColor = .label
    textView.tintColor = .systemBlue
    textView.adjustsFontForContentSizeCategory = true
    textView.keyboardDismissMode = .interactive
    textView.onReadOnlyAccessibilityActivate = { [weak self] in
      self?.activateReadOnlyEditor()
    }
    textView.onEditableAccessibilityActivate = { [weak self] in
      self?.toggleAccessibilityBoundary() ?? false
    }

    placeholderLabel.textColor = .placeholderText
    placeholderLabel.numberOfLines = 1
    placeholderLabel.isAccessibilityElement = false
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    textView.addSubview(placeholderLabel)
    NSLayoutConstraint.activate([
      placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
      placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
      placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
    ])

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
    tap.cancelsTouchesInView = false
    textView.addGestureRecognizer(tap)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setState":
      if let args = call.arguments as? [String: Any] {
        applyState(args)
      }
      result(nil)
    case "setFocus":
      let shouldFocus = call.arguments as? Bool ?? false
      if shouldFocus && !readOnly {
        textView.becomeFirstResponder()
      } else {
        textView.resignFirstResponder()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func activateReadOnlyEditor() {
    guard readOnly else { return }
    wantsFocusAfterReadOnlyActivation = true
    channel.invokeMethod("tap", arguments: nil)
  }

  private func toggleAccessibilityBoundary(announce: Bool = false) -> Bool {
    guard !readOnly else { return false }

    let textLength = (textView.text as NSString?)?.length ?? 0
    let selection = textView.selectedRange
    let destination = selection.length == 0 && selection.location == 0
      ? textLength
      : 0

    textView.selectedRange = NSRange(location: destination, length: 0)
    textView.scrollRangeToVisible(textView.selectedRange)
    textView.becomeFirstResponder()

    if announce && UIAccessibility.isVoiceOverRunning {
      let message = destination == 0 ? "插入點在開頭" : "插入點在結尾"
      DispatchQueue.main.async {
        UIAccessibility.post(notification: .announcement, argument: message)
      }
    }
    return true
  }

  @objc private func handleTap() {
    if readOnly {
      activateReadOnlyEditor()
    }
  }

  private func applyState(_ args: [String: Any]) {
    let text = args["text"] as? String ?? ""
    let emotes = args["emotes"] as? [[String: Any]] ?? []
    let fontSize = (args["fontSize"] as? NSNumber)?.doubleValue ?? 16
    let hintText = args["hintText"] as? String ?? ""
    let nextReadOnly = args["readOnly"] as? Bool ?? false
    let flutterHasFocus = args["hasFocus"] as? Bool ?? false
    let wasReadOnly = readOnly

    let base = (args["selectionBase"] as? NSNumber)?.intValue ?? text.utf16.count
    let extent = (args["selectionExtent"] as? NSNumber)?.intValue ?? base

    let signature = contentSignature(text: text, emotes: emotes, fontSize: fontSize)
    applyingFlutterState = true

    placeholderLabel.text = hintText
    placeholderLabel.font = UIFont.systemFont(ofSize: fontSize)
    textView.font = UIFont.systemFont(ofSize: fontSize)
    textView.typingAttributes = [
      .font: UIFont.systemFont(ofSize: fontSize),
      .foregroundColor: UIColor.label,
    ]

    if signature != lastContentSignature || textView.text != text {
      rebuildAttributedText(text: text, emotes: emotes, fontSize: fontSize)
      lastContentSignature = signature
    }

    readOnly = nextReadOnly
    textView.isEditable = !nextReadOnly
    textView.isSelectable = true
    if nextReadOnly {
      textView.resignFirstResponder()
    }

    let utf16Length = (text as NSString).length
    let safeBase = min(max(base, 0), utf16Length)
    let safeExtent = min(max(extent, 0), utf16Length)
    let location = min(safeBase, safeExtent)
    let length = abs(safeExtent - safeBase)
    textView.selectedRange = NSRange(location: location, length: length)
    textView.scrollRangeToVisible(textView.selectedRange)

    applyingFlutterState = false
    updatePlaceholder()
    reportHeightSoon()

    let shouldRestoreFocus = !nextReadOnly && (
      flutterHasFocus || (wasReadOnly && wantsFocusAfterReadOnlyActivation)
    )
    if shouldRestoreFocus {
      wantsFocusAfterReadOnlyActivation = false
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.readOnly else { return }
        self.textView.becomeFirstResponder()
      }
    }
  }

  private func contentSignature(
    text: String,
    emotes: [[String: Any]],
    fontSize: Double
  ) -> String {
    var parts = [text, "|\(fontSize)"]
    for emote in emotes {
      let start = (emote["start"] as? NSNumber)?.intValue ?? -1
      let label = emote["label"] as? String ?? ""
      let url = emote["url"] as? String ?? ""
      parts.append("|\(start):\(label):\(url)")
    }
    return parts.joined()
  }

  private func rebuildAttributedText(
    text: String,
    emotes: [[String: Any]],
    fontSize: Double
  ) {
    imageTasks.forEach { $0.cancel() }
    imageTasks.removeAll()

    let font = UIFont.systemFont(ofSize: fontSize)
    let mutable = NSMutableAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: UIColor.label,
      ]
    )
    let nsText = text as NSString

    for emote in emotes {
      guard let startNumber = emote["start"] as? NSNumber,
            let label = emote["label"] as? String,
            !label.isEmpty
      else {
        continue
      }

      let start = startNumber.intValue
      guard start >= 0, start < nsText.length else {
        continue
      }

      let range = NSRange(location: start, length: 1)
      guard nsText.substring(with: range) == "\u{FFFC}" else {
        continue
      }

      let attachment = IOSAccessibleTextAttachment()
      attachment.accessibilityLabel = label
      attachment.onAccessibilityActivate = { [weak self] in
        guard let self else { return false }
        if self.readOnly {
          self.activateReadOnlyEditor()
          return true
        }
        return self.toggleAccessibilityBoundary(announce: true)
      }
      attachment.bounds = CGRect(x: 0, y: -3, width: 22, height: 22)
      mutable.addAttribute(.attachment, value: attachment, range: range)

      if let urlString = emote["url"] as? String, !urlString.isEmpty {
        loadImage(urlString: urlString, attachment: attachment, range: range)
      }
    }

    textView.attributedText = mutable
    textView.typingAttributes = [
      .font: font,
      .foregroundColor: UIColor.label,
    ]
  }

  private func loadImage(
    urlString: String,
    attachment: NSTextAttachment,
    range: NSRange
  ) {
    let key = urlString as NSString
    if let cached = Self.imageCache.object(forKey: key) {
      attachment.image = cached
      return
    }

    guard let url = URL(string: urlString) else {
      return
    }

    let task = URLSession.shared.dataTask(with: url) { [weak self, weak attachment] data, _, _ in
      guard let self,
            let attachment,
            let data,
            let image = UIImage(data: data)
      else {
        return
      }

      Self.imageCache.setObject(image, forKey: key)
      DispatchQueue.main.async { [weak self, weak attachment] in
        guard let self, let attachment else { return }
        attachment.image = image
        self.textView.layoutManager.invalidateDisplay(forCharacterRange: range)
        self.textView.setNeedsDisplay()
      }
    }
    imageTasks.append(task)
    task.resume()
  }

  private func updatePlaceholder() {
    placeholderLabel.isHidden = !textView.text.isEmpty
  }

  private func composingRange() -> NSRange? {
    guard let marked = textView.markedTextRange else {
      return nil
    }
    let start = textView.offset(from: textView.beginningOfDocument, to: marked.start)
    let end = textView.offset(from: textView.beginningOfDocument, to: marked.end)
    guard start >= 0, end >= start else {
      return nil
    }
    return NSRange(location: start, length: end - start)
  }

  private func stateArguments(includeText: Bool) -> [String: Any] {
    let selection = textView.selectedRange
    let composing = composingRange()
    var args: [String: Any] = [
      "selectionBase": selection.location,
      "selectionExtent": selection.location + selection.length,
      "composingStart": composing?.location ?? -1,
      "composingEnd": composing.map { $0.location + $0.length } ?? -1,
    ]
    if includeText {
      args["text"] = textView.text ?? ""
    }
    return args
  }

  private func reportHeightSoon() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.textView.layoutIfNeeded()
      let height = max(self.textView.contentSize.height, 1)
      guard abs(height - self.lastReportedHeight) > 0.5 else {
        return
      }
      self.lastReportedHeight = height
      self.channel.invokeMethod("heightChanged", arguments: Double(height))
    }
  }

  func textViewDidBeginEditing(_ textView: UITextView) {
    channel.invokeMethod("focusChanged", arguments: true)
  }

  func textViewDidEndEditing(_ textView: UITextView) {
    channel.invokeMethod("focusChanged", arguments: false)
  }

  func textViewDidChange(_ textView: UITextView) {
    guard !applyingFlutterState else { return }
    updatePlaceholder()
    channel.invokeMethod("stateChanged", arguments: stateArguments(includeText: true))
    reportHeightSoon()
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    guard !applyingFlutterState else { return }
    channel.invokeMethod(
      "selectionChanged",
      arguments: stateArguments(includeText: false)
    )
  }
}

/// These elements are returned only by the link rotor, never inserted into
/// accessibilityElements, so ordinary swipes still read one complete comment.
private final class IOSRotorLink: UIAccessibilityElement {
  var activate: (() -> Void)?
  override func accessibilityActivate() -> Bool {
    guard let activate = activate else { return false }
    activate()
    return true
  }
}

private final class IOSTextLinkRotor {
  private let channel: FlutterMethodChannel
  private var hosts: [(host: NSObject, rotors: [UIAccessibilityCustomRotor]?)] = []
  private var targets: [IOSRotorLink] = []
  private var registrationId: Int?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "accessibilibili/text_link_rotor",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "focus":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int,
              let identifier = args["identifier"] as? String,
              let labels = args["labels"] as? [String]
        else {
          result(
            FlutterError(
              code: "invalid_rotor",
              message: "Invalid link rotor registration",
              details: nil
            )
          )
          return
        }
        self.clear()
        self.registrationId = id
        DispatchQueue.main.async { [weak self] in
          self?.install(id: id, identifier: identifier, labels: labels)
        }
        result(nil)
      case "clear":
        if let id = call.arguments as? Int, self.registrationId == id {
          self.clear()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func clear() {
    for entry in hosts {
      entry.host.accessibilityCustomRotors = entry.rotors
    }
    hosts.removeAll()
    targets.removeAll()
    registrationId = nil
  }

  private func matchingOwner(
    from focused: NSObject,
    identifier: String
  ) -> NSObject? {
    var current: AnyObject? = focused
    for _ in 0..<12 {
      if let object = current as? NSObject,
         let identified = object as? UIAccessibilityIdentification,
         identified.accessibilityIdentifier == identifier {
        return object
      }

      if let element = current as? UIAccessibilityElement,
         let container = element.accessibilityContainer as AnyObject? {
        current = container
      } else if let view = current as? UIView {
        current = view.superview
      } else {
        break
      }
    }
    return nil
  }

  private func install(
    id: Int,
    identifier: String,
    labels: [String],
    retries: Int = 3
  ) {
    guard registrationId == id,
          UIAccessibility.isVoiceOverRunning,
          let focused = UIAccessibility.focusedElement(
            using: .notificationVoiceOver
          ) as? NSObject
    else {
      if registrationId == id && retries > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
          self?.install(
            id: id,
            identifier: identifier,
            labels: labels,
            retries: retries - 1
          )
        }
      }
      return
    }

    guard let owner = matchingOwner(from: focused, identifier: identifier),
          !labels.isEmpty
    else {
      if registrationId == id && retries > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
          self?.install(
            id: id,
            identifier: identifier,
            labels: labels,
            retries: retries - 1
          )
        }
      }
      return
    }

    let rotor = UIAccessibilityCustomRotor(systemType: .link) {
      [weak self, weak owner] predicate in
      guard let self,
            let owner,
            self.registrationId == id,
            !labels.isEmpty
      else {
        return nil
      }

      let current = predicate.currentItem.targetElement as? IOSRotorLink
      let forward = predicate.searchDirection == .next
      let index: Int
      if let current,
         let position = self.targets.firstIndex(where: { $0 === current }) {
        index = position + (forward ? 1 : -1)
      } else {
        index = forward ? 0 : self.targets.count - 1
      }

      guard self.targets.indices.contains(index) else {
        return nil
      }

      let target = self.targets[index]
      target.accessibilityFrame = owner.accessibilityFrame
      return UIAccessibilityCustomRotorItemResult(
        targetElement: target,
        targetRange: nil
      )
    }

    let oldOwners = hosts
    hosts = []

    let targetList = labels.enumerated().map { index, label in
      let target = IOSRotorLink(accessibilityContainer: owner)
      target.isAccessibilityElement = true
      target.accessibilityLabel = label
      target.accessibilityTraits = .link
      target.accessibilityFrame = owner.accessibilityFrame
      target.activate = { [weak self] in
        guard let self, self.registrationId == id else {
          return
        }
        self.channel.invokeMethod(
          "activate",
          arguments: ["id": id, "index": index]
        )
      }
      return target
    }
    targets = targetList

    hosts.append((owner, owner.accessibilityCustomRotors))
    owner.accessibilityCustomRotors =
      (owner.accessibilityCustomRotors ?? []) + [rotor]

    if focused !== owner {
      hosts.append((focused, focused.accessibilityCustomRotors))
      focused.accessibilityCustomRotors =
        (focused.accessibilityCustomRotors ?? []) + [rotor]
    }

    _ = oldOwners
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var accessibilityChannel: FlutterMethodChannel?
  private var videoPhotoExporter: VideoPhotoExporter?
  private var textLinkRotor: IOSTextLinkRotor?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false // Disable shake to undo
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    textLinkRotor = IOSTextLinkRotor(messenger: engineBridge.applicationRegistrar.messenger())
    videoPhotoExporter = VideoPhotoExporter(messenger: engineBridge.applicationRegistrar.messenger())

    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AccessibilibiliRichTextEditor"
    ) {
      registrar.register(
        IOSRichTextEditorFactory(messenger: registrar.messenger()),
        withId: "accessibilibili/rich_text_editor"
      )
    }

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
        // Legacy Flutter rich-text fields may still send this while other
        // screens migrate to the native iOS editor. No runtime swizzle is used.
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
