import Flutter
import UIKit

/// Keeps Flutter's real viewport aligned with VoiceOver's virtual focus during
/// continuous reading without changing any Dart widget order or layout.
///
/// VoiceOver Read All can move through a few semantic nodes that Flutter has
/// already built just beyond the visible viewport. If the real scroll position
/// does not follow that virtual focus, the lazy semantics window eventually
/// runs out and Read All falls through to unrelated siblings such as the bottom
/// tab bar or a floating comment button.
///
/// UIKit exposes both a focus-change notification and a public API for querying
/// the element currently focused by VoiceOver. We use both. Whenever the focused
/// Flutter semantic item belongs to a vertical FlutterSemanticsScrollView and is
/// at/over the viewport edge, dispatch Flutter's own `showOnScreen` action for
/// that *same* semantic item. This is the primitive Flutter already uses for
/// ordinary VoiceOver swipe-to-focus navigation, so the lazy list can build the
/// next semantic batch before Read All exhausts the current one.
private enum VoiceOverViewportFollower {
  private static var focusObserver: NSObjectProtocol?
  private static var statusObserver: NSObjectProtocol?
  private static var pollTimer: Timer?
  private static var lastRepairObject: ObjectIdentifier?
  private static var lastRepairTime: TimeInterval = 0

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
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
  }()

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
      scrollView.window != nil,
      shouldBringFocusedItemInward(
        semanticObject,
        inside: scrollView
      )
    else {
      return
    }

    let objectID = ObjectIdentifier(semanticObject)
    let now = Date.timeIntervalSinceReferenceDate

    // Notifications and the polling fallback can report the same focus change.
    // Throttle only duplicate repairs for the same semantic object; if the
    // first request did not move the viewport, allow a retry shortly after.
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

    // Do not mutate the semantics tree while UIKit is delivering its focus
    // notification. Dispatching to the next main-loop turn also mirrors the
    // timing of Flutter's normal focus-driven showOnScreen path.
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
      // A focused Flutter semantic descendant inside a live vertical scrollable
      // is still safe to ask to show itself even if UIKit cannot give us a
      // reliable frame for an off-screen/hidden semantics node.
      return true
    }

    guard
      let native = nativeAccessibility(of: semanticObject),
      let itemFrame = accessibilityFrame(of: native)
    else {
      return true
    }

    // Keep a small inner band. Read All may focus a semantic node just beyond
    // the visible edge; bringing that node inward advances Flutter's lazy cache
    // without centering every item or creating large visual jumps.
    let verticalInset = min(48, max(12, viewport.height * 0.08))
    let safeViewport = viewport.insetBy(dx: 0, dy: verticalInset)

    if !viewport.intersects(itemFrame) {
      return true
    }

    if itemFrame.midY < safeViewport.minY || itemFrame.midY > safeViewport.maxY {
      return true
    }

    return false
  }

  private static func flutterSemanticObject(from focused: Any) -> NSObject? {
    guard let object = focused as? NSObject else {
      return nil
    }

    // Ordinary Flutter accessibility elements are SemanticsObject subclasses.
    if
      object.responds(to: NSSelectorFromString("nativeAccessibility")),
      object.responds(to: NSSelectorFromString("parent"))
    {
      return object
    }

    // FlutterSemanticsScrollView and SemanticsObjectContainer both expose their
    // wrapped semantics object through this Objective-C property.
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
    VoiceOverViewportFollower.install()
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
