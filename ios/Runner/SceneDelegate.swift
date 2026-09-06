import Flutter
import ObjectiveC.runtime
import UIKit

/// Temporary diagnostics for the iOS VoiceOver Read All boundary.
///
/// This version deliberately does not repair or page any Flutter list. It only
/// observes accessibility traversal and writes the latest trace to the iOS
/// clipboard so the failing and succeeding swipe paths can be compared without
/// Xcode/device logs.
private enum VoiceOverReadAllDiagnostics {
  private typealias VoidHandler = @convention(c) (
    AnyObject,
    Selector
  ) -> Void
  private typealias BoolChildHandler = @convention(c) (
    AnyObject,
    Selector,
    AnyObject
  ) -> Bool
  private typealias ScrollHandler = @convention(c) (
    AnyObject,
    Selector,
    Int
  ) -> Bool
  private typealias CountGetter = @convention(c) (
    AnyObject,
    Selector
  ) -> Int
  private typealias ElementGetter = @convention(c) (
    AnyObject,
    Selector,
    Int
  ) -> AnyObject?
  private typealias IndexGetter = @convention(c) (
    AnyObject,
    Selector,
    AnyObject
  ) -> Int

  private static var events: [String] = []
  private static let maxEvents = 180
  private static var startTime = Date.timeIntervalSinceReferenceDate
  private static var clipboardWorkItem: DispatchWorkItem?
  private static var focusObserver: NSObjectProtocol?
  private static var statusObserver: NSObjectProtocol?

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    startFreshTrace(reason: "launch")

    guard
      let semanticsClass = NSClassFromString("SemanticsObject"),
      let containerClass = NSClassFromString("SemanticsObjectContainer"),
      let scrollViewClass = NSClassFromString("FlutterSemanticsScrollView")
    else {
      record("ERR", "Flutter accessibility runtime classes missing")
      return
    }

    installSemanticHooks(on: semanticsClass)
    installContainerHooks(on: containerClass)
    installScrollHook(
      on: scrollViewClass,
      selectorName: "accessibilityScroll:",
      code: "RV"
    )
    installPublicFocusNotifications()

    record("READY", "diagnostics installed")
  }()

  // MARK: - Semantic object events

  private static func installSemanticHooks(on semanticsClass: AnyClass) {
    installVoidHook(
      on: semanticsClass,
      selectorName: "accessibilityElementDidBecomeFocused",
      code: "F"
    )
    installVoidHook(
      on: semanticsClass,
      selectorName: "showOnScreen",
      code: "S"
    )
    installChildBoolHook(
      on: semanticsClass,
      selectorName: "accessibilityScrollToVisibleWithChild:",
      code: "VC"
    )
    installScrollHook(
      on: semanticsClass,
      selectorName: "accessibilityScroll:",
      code: "RS"
    )
  }

  private static func installVoidHook(
    on targetClass: AnyClass,
    selectorName: String,
    code: String
  ) {
    let selector = NSSelectorFromString(selectorName)
    guard let method = class_getInstanceMethod(targetClass, selector) else {
      record("MISS", selectorName)
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: VoidHandler.self
    )

    let block: @convention(block) (AnyObject) -> Void = { object in
      record(code, "before \(describe(object))")
      original(object, selector)
      record(code, "after  \(describe(object))")
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installChildBoolHook(
    on targetClass: AnyClass,
    selectorName: String,
    code: String
  ) {
    let selector = NSSelectorFromString(selectorName)
    guard let method = class_getInstanceMethod(targetClass, selector) else {
      record("MISS", selectorName)
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: BoolChildHandler.self
    )

    let block: @convention(block) (AnyObject, AnyObject) -> Bool = {
      object,
      child in
      record(
        code,
        "parent{\(describe(object))} child{\(describe(child))}"
      )
      let result = original(object, selector, child)
      record(
        code,
        "ret=\(result ? 1 : 0) child{\(describe(child))}"
      )
      return result
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installScrollHook(
    on targetClass: AnyClass,
    selectorName: String,
    code: String
  ) {
    let selector = NSSelectorFromString(selectorName)
    guard let method = class_getInstanceMethod(targetClass, selector) else {
      record("MISS", selectorName)
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: ScrollHandler.self
    )

    let block: @convention(block) (AnyObject, Int) -> Bool = {
      object,
      rawDirection in
      let direction = scrollDirectionName(rawDirection)
      record(code, "dir=\(direction) before \(describe(object))")
      let result = original(object, selector, rawDirection)
      record(
        code,
        "dir=\(direction) ret=\(result ? 1 : 0) after \(describe(object))"
      )
      return result
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  // MARK: - Flutter semantics container traversal

  private static func installContainerHooks(on containerClass: AnyClass) {
    let countSelector = NSSelectorFromString("accessibilityElementCount")
    let elementSelector = NSSelectorFromString("accessibilityElementAtIndex:")
    let indexSelector = NSSelectorFromString("indexOfAccessibilityElement:")

    guard
      let countMethod = class_getInstanceMethod(containerClass, countSelector),
      let elementMethod = class_getInstanceMethod(containerClass, elementSelector),
      let indexMethod = class_getInstanceMethod(containerClass, indexSelector)
    else {
      record("MISS", "SemanticsObjectContainer traversal methods")
      return
    }

    let originalCount = unsafeBitCast(
      method_getImplementation(countMethod),
      to: CountGetter.self
    )
    let originalElement = unsafeBitCast(
      method_getImplementation(elementMethod),
      to: ElementGetter.self
    )
    let originalIndex = unsafeBitCast(
      method_getImplementation(indexMethod),
      to: IndexGetter.self
    )

    let elementBlock: @convention(block) (
      AnyObject,
      Int
    ) -> AnyObject? = { container, index in
      let count = originalCount(container, countSelector)
      let element = originalElement(container, elementSelector, index)

      // The reproducible boundary is roughly 2-3 items wide. Logging the final
      // five entries keeps the clipboard useful without drowning it in noise.
      if index >= max(0, count - 5) {
        let description = element.map(describe) ?? "nil"
        record("E", "i=\(index)/\(count) \(description)")
      }
      return element
    }

    let indexBlock: @convention(block) (
      AnyObject,
      AnyObject
    ) -> Int = { container, element in
      let result = originalIndex(container, indexSelector, element)
      let count = originalCount(container, countSelector)
      if result >= max(0, count - 5) || result < 0 {
        record("I", "i=\(result)/\(count) \(describe(element))")
      }
      return result
    }

    method_setImplementation(
      elementMethod,
      imp_implementationWithBlock(elementBlock)
    )
    method_setImplementation(
      indexMethod,
      imp_implementationWithBlock(indexBlock)
    )
  }

  // MARK: - Public UIKit focus notification

  private static func installPublicFocusNotifications() {
    focusObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.elementFocusedNotification,
      object: nil,
      queue: .main
    ) { _ in
      // Do not read focusedElementUserInfoKey here. In the Xcode/iOS SDK used
      // by CI, that dictionary value is imported as `Any`, while
      // UIAccessibility.focusedElement(using:) is also `Any?`. Trying to merge
      // either value through `AnyObject?` makes Swift's class-constrained type
      // inference fail. The public query API alone provides the same VoiceOver
      // virtual focus needed by this diagnostic.
      guard let rawFocused = UIAccessibility.focusedElement(
        using: .notificationVoiceOver
      ) else {
        record("NF", "nil")
        return
      }

      guard let focused = rawFocused as? NSObject else {
        record(
          "NF",
          "c=\(String(describing: type(of: rawFocused))) no-nsobject"
        )
        return
      }

      record("NF", describe(focused))
    }

    statusObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.voiceOverStatusDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      startFreshTrace(
        reason: UIAccessibility.isVoiceOverRunning ? "vo-on" : "vo-off"
      )
    }
  }

  // MARK: - Trace formatting

  private static func describe(_ object: AnyObject) -> String {
    let className = String(describing: type(of: object))

    guard let semantic = flutterSemanticObject(from: object) else {
      return "c=\(className) no-sem"
    }

    let uid = semanticUID(semantic).map(String.init) ?? "?"

    guard let scrollView = verticalFlutterScrollAncestor(of: semantic) else {
      return "c=\(className) uid=\(uid) list=0"
    }

    let position = scrollPosition(scrollView)
    let relation = viewportRelation(of: semantic, in: scrollView)
    let tail = tailDistance(of: semantic, in: scrollView)
      .map(String.init) ?? "?"

    return "c=\(className) uid=\(uid) list=1 tail=\(tail) rel=\(relation) \(position)"
  }

  private static func flutterSemanticObject(from object: AnyObject) -> NSObject? {
    guard let value = object as? NSObject else {
      return nil
    }

    if
      value.responds(to: NSSelectorFromString("nativeAccessibility")),
      value.responds(to: NSSelectorFromString("parent"))
    {
      return value
    }

    let selector = NSSelectorFromString("semanticsObject")
    if
      value.responds(to: selector),
      let semantic = value.value(forKey: "semanticsObject") as? NSObject
    {
      return semantic
    }

    return nil
  }

  private static func verticalFlutterScrollAncestor(
    of semantic: NSObject
  ) -> UIScrollView? {
    var current: NSObject? = semantic

    while let node = current {
      if
        let native = nativeAccessibility(of: node),
        let scrollView = native as? UIScrollView,
        String(describing: type(of: scrollView)).contains(
          "FlutterSemanticsScrollView"
        ),
        scrollView.contentSize.height > scrollView.bounds.height + 1
      {
        return scrollView
      }
      current = semanticParent(of: node)
    }

    return nil
  }

  private static func tailDistance(
    of semantic: NSObject,
    in scrollView: UIScrollView
  ) -> Int? {
    guard let owner = semanticsObject(of: scrollView) else {
      return nil
    }

    var ordered: [NSObject] = []
    for child in semanticChildren(of: owner) {
      collectFocusableSemantics(child, into: &ordered)
    }

    guard let index = ordered.firstIndex(where: { $0 === semantic }) else {
      return nil
    }
    return ordered.count - 1 - index
  }

  private static func collectFocusableSemantics(
    _ object: NSObject,
    into result: inout [NSObject]
  ) {
    if isFocusableSemanticObject(object) {
      result.append(object)
    }
    for child in semanticChildren(of: object) {
      collectFocusableSemantics(child, into: &result)
    }
  }

  private static func viewportRelation(
    of semantic: NSObject,
    in scrollView: UIScrollView
  ) -> String {
    guard
      let viewport = screenFrame(of: scrollView),
      let native = nativeAccessibility(of: semantic),
      let item = accessibilityFrame(of: native)
    else {
      return "?"
    }

    if item.maxY < viewport.minY {
      return "above"
    }
    if item.minY > viewport.maxY {
      return "below"
    }

    let edge = min(56, max(16, viewport.height * 0.10))
    if item.midY <= viewport.minY + edge {
      return "top"
    }
    if item.midY >= viewport.maxY - edge {
      return "bottom"
    }
    return "inside"
  }

  private static func scrollPosition(_ scrollView: UIScrollView) -> String {
    let maxOffset = max(
      0,
      scrollView.contentSize.height - scrollView.bounds.height
    )
    return String(
      format: "off=%.0f/%.0f",
      scrollView.contentOffset.y,
      maxOffset
    )
  }

  private static func semanticUID(_ object: NSObject) -> Int? {
    let selector = NSSelectorFromString("uid")
    guard object.responds(to: selector) else {
      return nil
    }

    if let number = object.value(forKey: "uid") as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private static func semanticChildren(of object: NSObject) -> [NSObject] {
    let selector = NSSelectorFromString("children")
    guard
      object.responds(to: selector),
      let children = object.value(forKey: "children") as? NSArray
    else {
      return []
    }
    return children.compactMap { $0 as? NSObject }
  }

  private static func semanticParent(of object: NSObject) -> NSObject? {
    let selector = NSSelectorFromString("parent")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "parent") as? NSObject
  }

  private static func semanticsObject(of object: NSObject) -> NSObject? {
    let selector = NSSelectorFromString("semanticsObject")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "semanticsObject") as? NSObject
  }

  private static func nativeAccessibility(of object: NSObject) -> AnyObject? {
    let selector = NSSelectorFromString("nativeAccessibility")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "nativeAccessibility") as AnyObject?
  }

  private static func isFocusableSemanticObject(_ object: NSObject) -> Bool {
    guard let native = nativeAccessibility(of: object) else {
      return false
    }
    if let element = native as? UIAccessibilityElement {
      return element.isAccessibilityElement
    }
    if let view = native as? UIView {
      return view.isAccessibilityElement
    }
    return false
  }

  private static func accessibilityFrame(of object: AnyObject) -> CGRect? {
    if let element = object as? UIAccessibilityElement {
      return validFrame(element.accessibilityFrame)
    }
    if let view = object as? UIView {
      return screenFrame(of: view)
    }
    return nil
  }

  private static func validFrame(_ frame: CGRect) -> CGRect? {
    guard !frame.isNull, !frame.isInfinite, !frame.isEmpty else {
      return nil
    }
    return frame
  }

  private static func screenFrame(of view: UIView) -> CGRect? {
    guard let window = view.window else {
      return nil
    }
    let frameInWindow = view.convert(view.bounds, to: window)
    return window.convert(frameInWindow, to: nil)
  }

  private static func scrollDirectionName(_ raw: Int) -> String {
    guard let direction = UIAccessibilityScrollDirection(rawValue: raw) else {
      return "raw\(raw)"
    }

    switch direction {
    case .right: return "right"
    case .left: return "left"
    case .up: return "up"
    case .down: return "down"
    case .next: return "next"
    case .previous: return "previous"
    @unknown default: return "raw\(raw)"
    }
  }

  private static func startFreshTrace(reason: String) {
    DispatchQueue.main.async {
      startTime = Date.timeIntervalSinceReferenceDate
      events.removeAll(keepingCapacity: true)
      record("START", reason)
    }
  }

  private static func record(_ code: String, _ detail: String) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async {
        record(code, detail)
      }
      return
    }

    let elapsed = Date.timeIntervalSinceReferenceDate - startTime
    let line = String(format: "%07.3f %@ %@", elapsed, code, detail)
    events.append(line)

    if events.count > maxEvents {
      events.removeFirst(events.count - maxEvents)
    }

    scheduleClipboardUpdate()
  }

  private static func scheduleClipboardUpdate() {
    clipboardWorkItem?.cancel()

    let work = DispatchWorkItem {
      let header = "ACCESSIBILIBILI_READALL_DIAG_V1"
      UIPasteboard.general.string = ([header] + events).joined(separator: "\n")
    }

    clipboardWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
  }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    VoiceOverReadAllDiagnostics.install()
    super.scene(
      scene,
      willConnectTo: session,
      options: connectionOptions
    )
  }

  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for windowScene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    return .minimal
  }
}
