import Flutter
import ObjectiveC.runtime
import UIKit

/// Keeps VoiceOver Read All moving through Flutter lazy lists by restoring the
/// exact scroll-to-visible step that iOS performs for ordinary one-finger
/// navigation.
///
/// Device diagnostics showed a clean difference between the failing Read All
/// path and the succeeding manual right-swipe path: the successful path calls
/// `accessibilityScrollToVisibleWithChild:` and then `showOnScreen`, after which
/// Flutter immediately exposes a new batch of semantic nodes. Read All can
/// enumerate already-built off-screen semantic children, but it does not make
/// that scroll-to-visible call before the lazy semantic window is exhausted.
///
/// This patch observes Flutter's native accessibility container enumeration.
/// When VoiceOver asks a SemanticsObjectContainer for a real, focusable Flutter
/// semantic element that is already outside the app window, schedule the same
/// `accessibilityScrollToVisibleWithChild(element)` call that Flutter receives
/// during successful swipe navigation. Flutter then dispatches its own
/// SemanticsAction.showOnScreen and decides how far the owning Scrollable needs
/// to move. No Dart layout, cache extent, navigation bar, or comment UI changes.
private enum VoiceOverReadAllScrollToVisiblePatch {
  private typealias ElementGetter = @convention(c) (
    AnyObject,
    Selector,
    Int
  ) -> AnyObject?
  private typealias BoolChildHandler = @convention(c) (
    AnyObject,
    Selector,
    AnyObject
  ) -> Bool

  private static var repairInFlight = false
  private static var lastRepairObject: ObjectIdentifier?
  private static var lastRepairTime: TimeInterval = 0

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard let containerClass = NSClassFromString("SemanticsObjectContainer") else {
      return
    }

    let selector = NSSelectorFromString("accessibilityElementAtIndex:")
    guard let method = class_getInstanceMethod(containerClass, selector) else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: ElementGetter.self
    )

    let block: @convention(block) (
      AnyObject,
      Int
    ) -> AnyObject? = { container, index in
      let element = original(container, selector, index)

      guard
        UIAccessibility.isVoiceOverRunning,
        Thread.isMainThread,
        let element,
        shouldRequestScrollToVisible(for: element)
      else {
        return element
      }

      scheduleScrollToVisible(for: element)
      return element
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }()

  private static func shouldRequestScrollToVisible(
    for object: AnyObject
  ) -> Bool {
    guard
      let semantic = object as? NSObject,
      semantic.responds(
        to: NSSelectorFromString("accessibilityScrollToVisibleWithChild:")
      ),
      semantic.responds(to: NSSelectorFromString("showOnScreen")),
      let element = object as? UIAccessibilityElement,
      element.isAccessibilityElement
    else {
      return false
    }

    let frame = element.accessibilityFrame

    // Flutter's hidden/off-screen semantic nodes may report an empty/invalid
    // native frame. Those are precisely the nodes that need showOnScreen.
    if frame.isNull || frame.isInfinite || frame.isEmpty {
      return true
    }

    guard let windowFrame = activeWindowScreenFrame() else {
      return false
    }

    // Only repair genuinely off-screen nodes (plus a tiny two-point tolerance)
    // rather than every element VoiceOver enumerates. This avoids moving an
    // ordinary list merely because UIKit probes its accessibility hierarchy.
    let tolerance: CGFloat = 2
    if frame.minY >= windowFrame.maxY - tolerance {
      return true
    }
    if frame.maxY <= windowFrame.minY + tolerance {
      return true
    }

    return false
  }

  private static func scheduleScrollToVisible(for object: AnyObject) {
    guard let semantic = object as? NSObject else {
      return
    }

    let objectID = ObjectIdentifier(semantic)
    let now = Date.timeIntervalSinceReferenceDate

    // SemanticsObjectContainer can be queried repeatedly for the same element
    // during one VoiceOver traversal. One request is enough; Flutter's semantic
    // update will cause a fresh enumeration when the viewport has advanced.
    if
      lastRepairObject == objectID,
      now - lastRepairTime < 0.60
    {
      return
    }

    // A single showOnScreen can synchronously trigger a semantics rebuild.
    // Serialize repairs so that a burst of speculative accessibility queries
    // cannot jump several rows before VoiceOver has spoken them.
    guard !repairInFlight else {
      return
    }

    lastRepairObject = objectID
    lastRepairTime = now
    repairInFlight = true

    DispatchQueue.main.async {
      guard UIAccessibility.isVoiceOverRunning else {
        finishRepair()
        return
      }

      _ = invokeScrollToVisible(on: semantic)

      // Give Flutter one frame plus a little room to publish its new semantics
      // batch before allowing another off-screen candidate to advance the list.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
        finishRepair()
      }
    }
  }

  private static func invokeScrollToVisible(on semantic: NSObject) -> Bool {
    let selector = NSSelectorFromString("accessibilityScrollToVisibleWithChild:")
    guard
      semantic.responds(to: selector),
      let method = class_getInstanceMethod(type(of: semantic), selector)
    else {
      return false
    }

    let handler = unsafeBitCast(
      method_getImplementation(method),
      to: BoolChildHandler.self
    )

    // This intentionally mirrors the exact successful sequence captured on the
    // device: VC parent{item} child{item} -> showOnScreen -> VC ret=1.
    return handler(semantic, selector, semantic)
  }

  private static func finishRepair() {
    repairInFlight = false
  }

  private static func activeWindowScreenFrame() -> CGRect? {
    var fallback: UIWindow?

    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else {
        continue
      }

      for window in windowScene.windows where !window.isHidden && window.alpha > 0 {
        if window.isKeyWindow {
          return screenFrame(of: window)
        }
        if fallback == nil {
          fallback = window
        }
      }
    }

    if let fallback {
      return screenFrame(of: fallback)
    }
    return nil
  }

  private static func screenFrame(of view: UIView) -> CGRect? {
    guard let window = view.window ?? (view as? UIWindow) else {
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
    VoiceOverReadAllScrollToVisiblePatch.install()
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
