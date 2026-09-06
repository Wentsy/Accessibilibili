import Flutter
import ObjectiveC.runtime
import UIKit

/// Keeps Flutter's real viewport aligned with VoiceOver during continuous
/// reading and bridges the *actual screen-level* Read All boundary back to the
/// vertical Flutter list the user was reading.
///
/// There are two complementary pieces here:
///
/// 1. UIKit exposes both focus notifications and a public API for querying the
///    element currently focused by VoiceOver. If Read All reaches one of the
///    semantic nodes Flutter prebuilt just outside the viewport, ask that same
///    node to `showOnScreen`. This lets the lazy semantics window follow along.
///
/// 2. Read All does not consider the last list row to be the end of the page if
///    the Flutter screen has later sibling controls. In this app that is why a
///    comment page continues into "發表評論", and the home feed continues into
///    the bottom tabs. Apple documents `causesPageTurn` on the *last readable
///    element of the page*, paired with `accessibilityScroll(.next)`. We mark
///    the true final focusable Flutter semantic element of the screen, remember
///    the vertical list that contained the user's pre-Read-All focus, and route
///    that automatic `.next` page request back into that list as `.up` (Flutter
///    maps `.up` to SemanticsAction.scrollDown).
///
/// No Dart widget order, FAB placement, bottom navigation, or cache extent is
/// changed.
private enum VoiceOverContinuousReadBridge {
  private typealias TraitsGetter = @convention(c) (
    AnyObject,
    Selector
  ) -> UInt64
  private typealias ScrollHandler = @convention(c) (
    AnyObject,
    Selector,
    Int
  ) -> Bool

  private final class WeakScrollBox {
    weak var value: UIScrollView?
  }

  private static let activeVerticalScroll = WeakScrollBox()
  private static var focusObserver: NSObjectProtocol?
  private static var statusObserver: NSObjectProtocol?
  private static var pollTimer: Timer?
  private static var lastRepairObject: ObjectIdentifier?
  private static var lastRepairTime: TimeInterval = 0

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    installPageTurnHooks()
    installFocusTracking()
  }()

  // MARK: - Screen-level Read All page turn

  private static func installPageTurnHooks() {
    guard
      let flutterSemanticClass = NSClassFromString("FlutterSemanticsObject"),
      let semanticsBaseClass = NSClassFromString("SemanticsObject")
    else {
      return
    }

    installRootTailTraitHook(on: flutterSemanticClass)
    installSemanticScrollHook(on: semanticsBaseClass)

    if let flutterViewControllerClass = NSClassFromString("FlutterViewController") {
      installViewControllerScrollFallback(on: flutterViewControllerClass)
    }
  }

  private static func installRootTailTraitHook(on semanticClass: AnyClass) {
    let selector = NSSelectorFromString("accessibilityTraits")
    guard let method = class_getInstanceMethod(semanticClass, selector) else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: TraitsGetter.self
    )

    let block: @convention(block) (AnyObject) -> UInt64 = { object in
      let rawTraits = original(object, selector)
      guard isCurrentScreenReadAllTail(object) else {
        return rawTraits
      }

      var traits = UIAccessibilityTraits(rawValue: rawTraits)
      traits.insert(.causesPageTurn)
      return traits.rawValue
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installSemanticScrollHook(on semanticsBaseClass: AnyClass) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard let method = class_getInstanceMethod(semanticsBaseClass, selector) else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: ScrollHandler.self
    )

    let block: @convention(block) (AnyObject, Int) -> Bool = {
      object,
      rawDirection in
      guard
        UIAccessibility.isVoiceOverRunning,
        let direction = UIAccessibilityScrollDirection(rawValue: rawDirection),
        direction == .next,
        let scrollView = activeReadableScroll(),
        isCurrentScreenReadAllTail(object) || isRootSemanticObject(object)
      else {
        return original(object, selector, rawDirection)
      }

      return performForwardPageTurn(on: scrollView)
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installViewControllerScrollFallback(
    on viewControllerClass: AnyClass
  ) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard
      let inheritedMethod = class_getInstanceMethod(
        viewControllerClass,
        selector
      ),
      let typeEncoding = method_getTypeEncoding(inheritedMethod)
    else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(inheritedMethod),
      to: ScrollHandler.self
    )

    let block: @convention(block) (AnyObject, Int) -> Bool = {
      object,
      rawDirection in
      guard
        UIAccessibility.isVoiceOverRunning,
        let direction = UIAccessibilityScrollDirection(rawValue: rawDirection),
        direction == .next,
        let scrollView = activeReadableScroll()
      else {
        return original(object, selector, rawDirection)
      }

      return performForwardPageTurn(on: scrollView)
    }

    let replacement = imp_implementationWithBlock(block)

    // Add an override when FlutterViewController inherits UIKit's method so we
    // never mutate UIViewController's global implementation.
    if !class_addMethod(
      viewControllerClass,
      selector,
      replacement,
      typeEncoding
    ) {
      guard let ownMethod = class_getInstanceMethod(
        viewControllerClass,
        selector
      ) else {
        return
      }
      method_setImplementation(ownMethod, replacement)
    }
  }

  private static func isCurrentScreenReadAllTail(_ object: AnyObject) -> Bool {
    guard
      UIAccessibility.isVoiceOverRunning,
      activeReadableScroll() != nil,
      let semanticObject = object as? NSObject,
      let root = rootSemanticAncestor(of: semanticObject),
      let tail = lastFocusableDescendant(root),
      tail === semanticObject
    else {
      return false
    }

    return true
  }

  private static func isRootSemanticObject(_ object: AnyObject) -> Bool {
    guard let semanticObject = object as? NSObject else {
      return false
    }
    return semanticParent(of: semanticObject) == nil &&
      semanticObject.responds(to: NSSelectorFromString("nativeAccessibility"))
  }

  private static func rootSemanticAncestor(of object: NSObject) -> NSObject? {
    var current: NSObject? = object
    var last: NSObject?

    while let node = current {
      last = node
      current = semanticParent(of: node)
    }

    return last
  }

  private static func lastFocusableDescendant(_ object: NSObject) -> NSObject? {
    for child in semanticChildren(of: object).reversed() {
      if let result = lastFocusableDescendant(child) {
        return result
      }
    }

    return isFocusableSemanticObject(object) ? object : nil
  }

  private static func activeReadableScroll() -> UIScrollView? {
    guard
      let scrollView = activeVerticalScroll.value,
      scrollView.window != nil,
      isVerticalScrollable(scrollView),
      hasRemainingForwardRange(scrollView)
    else {
      return nil
    }
    return scrollView
  }

  private static func performForwardPageTurn(on scrollView: UIScrollView) -> Bool {
    guard
      isVerticalScrollable(scrollView),
      hasRemainingForwardRange(scrollView)
    else {
      return false
    }

    // FlutterSemanticsScrollView forwards this to its SemanticsObject. Flutter
    // maps `.up` to SemanticsAction.scrollDown (forward in a vertical list).
    let handled = scrollView.accessibilityScroll(.up)
    if handled {
      weak var weakScrollView = scrollView
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        guard
          UIAccessibility.isVoiceOverRunning,
          weakScrollView?.window != nil
        else {
          return
        }
        UIAccessibility.post(notification: .pageScrolled, argument: nil)
      }
    }
    return handled
  }

  // MARK: - Keep the real viewport following VoiceOver's virtual focus

  private static func installFocusTracking() {
    focusObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.elementFocusedNotification,
      object: nil,
      queue: .main
    ) { notification in
      guard UIAccessibility.isVoiceOverRunning else { return }

      if
        let focused = notification.userInfo?[
          UIAccessibility.focusedElementUserInfoKey
        ]
      {
        followVoiceOverFocus(focused)
      } else if let focused = UIAccessibility.focusedElement(
        using: .notificationVoiceOver
      ) {
        followVoiceOverFocus(focused)
      }
    }

    statusObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.voiceOverStatusDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      if UIAccessibility.isVoiceOverRunning {
        startPolling()
      } else {
        stopPolling()
      }
    }

    if UIAccessibility.isVoiceOverRunning {
      startPolling()
    }
  }

  private static func startPolling() {
    stopPolling()

    let timer = Timer(timeInterval: 0.12, repeats: true) { _ in
      guard
        UIAccessibility.isVoiceOverRunning,
        let focused = UIAccessibility.focusedElement(
          using: .notificationVoiceOver
        )
      else {
        return
      }
      followVoiceOverFocus(focused)
    }

    pollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private static func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
    activeVerticalScroll.value = nil
    lastRepairObject = nil
    lastRepairTime = 0
  }

  private static func followVoiceOverFocus(_ focused: Any) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async {
        followVoiceOverFocus(focused)
      }
      return
    }

    guard
      let semanticObject = flutterSemanticObject(from: focused),
      let scrollView = verticalFlutterScrollAncestor(of: semanticObject),
      scrollView.window != nil
    else {
      // If Read All later moves to a sibling control such as the comment FAB or
      // bottom navigation, deliberately keep the last vertical list remembered.
      // That is the page we must advance when the screen-level tail requests
      // `.next`.
      return
    }

    activeVerticalScroll.value = scrollView

    guard shouldBringFocusedItemInward(semanticObject, inside: scrollView) else {
      return
    }

    let objectID = ObjectIdentifier(semanticObject)
    let now = Date.timeIntervalSinceReferenceDate

    if
      lastRepairObject == objectID,
      now - lastRepairTime < 0.28
    {
      return
    }

    lastRepairObject = objectID
    lastRepairTime = now

    let selector = NSSelectorFromString("showOnScreen")
    guard semanticObject.responds(to: selector) else {
      return
    }

    DispatchQueue.main.async {
      guard
        UIAccessibility.isVoiceOverRunning,
        semanticObject.responds(to: selector),
        verticalFlutterScrollAncestor(of: semanticObject)?.window != nil
      else {
        return
      }
      _ = semanticObject.perform(selector)
    }
  }

  private static func shouldBringFocusedItemInward(
    _ semanticObject: NSObject,
    inside scrollView: UIScrollView
  ) -> Bool {
    guard let viewport = screenFrame(of: scrollView) else {
      return true
    }

    guard
      let native = nativeAccessibility(of: semanticObject),
      let itemFrame = accessibilityFrame(of: native)
    else {
      return true
    }

    let verticalInset = min(48, max(12, viewport.height * 0.08))
    let safeViewport = viewport.insetBy(dx: 0, dy: verticalInset)

    if !viewport.intersects(itemFrame) {
      return true
    }

    return itemFrame.midY < safeViewport.minY ||
      itemFrame.midY > safeViewport.maxY
  }

  // MARK: - Flutter semantics runtime helpers

  private static func flutterSemanticObject(from focused: Any) -> NSObject? {
    guard let object = focused as? NSObject else {
      return nil
    }

    if
      object.responds(to: NSSelectorFromString("nativeAccessibility")),
      object.responds(to: NSSelectorFromString("parent"))
    {
      return object
    }

    let selector = NSSelectorFromString("semanticsObject")
    if
      object.responds(to: selector),
      let semanticObject = object.value(forKey: "semanticsObject") as? NSObject
    {
      return semanticObject
    }

    return nil
  }

  private static func verticalFlutterScrollAncestor(
    of semanticObject: NSObject
  ) -> UIScrollView? {
    var current: NSObject? = semanticObject

    while let node = current {
      if
        let native = nativeAccessibility(of: node),
        let scrollView = native as? UIScrollView,
        NSStringFromClass(type(of: scrollView)).contains(
          "FlutterSemanticsScrollView"
        ),
        isVerticalScrollable(scrollView)
      {
        return scrollView
      }

      current = semanticParent(of: node)
    }

    return nil
  }

  private static func semanticChildren(of object: NSObject) -> [NSObject] {
    let selector = NSSelectorFromString("children")
    guard
      object.responds(to: selector),
      let rawChildren = object.value(forKey: "children") as? NSArray
    else {
      return []
    }

    return rawChildren.compactMap { $0 as? NSObject }
  }

  private static func semanticParent(of object: NSObject) -> NSObject? {
    let selector = NSSelectorFromString("parent")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "parent") as? NSObject
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

  private static func isVerticalScrollable(_ scrollView: UIScrollView) -> Bool {
    scrollView.bounds.height > 1 &&
      scrollView.contentSize.height > scrollView.bounds.height + 1
  }

  private static func hasRemainingForwardRange(_ scrollView: UIScrollView) -> Bool {
    let maxOffset = max(
      0,
      scrollView.contentSize.height - scrollView.bounds.height
    )
    return scrollView.contentOffset.y < maxOffset - 1
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
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    VoiceOverContinuousReadBridge.install()
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
