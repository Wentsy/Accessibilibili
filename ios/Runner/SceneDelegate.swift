import Flutter
import ObjectiveC.runtime
import UIKit

/// Bridges VoiceOver's automatic Read All page turns to Flutter's vertical
/// semantics scrolling without changing the Dart widget/layout structure.
///
/// Flutter exposes every scrollable semantics node through a hidden native
/// `FlutterSemanticsScrollView`. Read All can ask UIKit for the next page by
/// sending `.next`, while Flutter interprets `.next` as a horizontal action.
/// Mark the last *currently readable* semantic element in a vertical viewport
/// with `causesPageTurn`, then translate that automatic `.next` request into
/// `.up`, which Flutter maps to forward/downward vertical scrolling.
private enum VoiceOverContinuousReadPatch {
  private typealias TraitsGetter = @convention(c) (
    AnyObject,
    Selector
  ) -> UInt64
  private typealias ScrollHandler = @convention(c) (
    AnyObject,
    Selector,
    Int
  ) -> Bool

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let semanticClass = NSClassFromString("FlutterSemanticsObject"),
      let semanticsBaseClass = NSClassFromString("SemanticsObject"),
      let semanticsContainerClass = NSClassFromString("SemanticsObjectContainer"),
      let scrollViewClass = NSClassFromString("FlutterSemanticsScrollView")
    else {
      return
    }

    installTraitsHook(
      semanticClass: semanticClass,
      scrollViewClass: scrollViewClass
    )

    installScrollHook(
      on: semanticsBaseClass,
      scrollViewClass: scrollViewClass,
      requirePageBoundary: true
    )
    installScrollHook(
      on: semanticsContainerClass,
      scrollViewClass: scrollViewClass,
      requirePageBoundary: false
    )
    installScrollHook(
      on: scrollViewClass,
      scrollViewClass: scrollViewClass,
      requirePageBoundary: false
    )
  }()

  private static func installTraitsHook(
    semanticClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
    let selector = NSSelectorFromString("accessibilityTraits")
    guard let method = class_getInstanceMethod(semanticClass, selector) else {
      return
    }

    let originalIMP = method_getImplementation(method)
    let original = unsafeBitCast(originalIMP, to: TraitsGetter.self)

    let block: @convention(block) (AnyObject) -> UInt64 = { object in
      let rawTraits = original(object, selector)
      guard shouldOfferForwardPageTurn(
        for: object,
        scrollViewClass: scrollViewClass
      ) else {
        return rawTraits
      }

      var traits = UIAccessibilityTraits(rawValue: rawTraits)
      traits.insert(.causesPageTurn)
      return traits.rawValue
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installScrollHook(
    on targetClass: AnyClass,
    scrollViewClass: AnyClass,
    requirePageBoundary: Bool
  ) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard let method = class_getInstanceMethod(targetClass, selector) else {
      return
    }

    let originalIMP = method_getImplementation(method)
    let original = unsafeBitCast(originalIMP, to: ScrollHandler.self)

    let block: @convention(block) (AnyObject, Int) -> Bool = {
      object,
      rawDirection in
      guard
        UIAccessibility.isVoiceOverRunning,
        let direction = UIAccessibilityScrollDirection(rawValue: rawDirection),
        direction == .next,
        let scrollView = nearestVerticalFlutterScrollView(
          for: object,
          scrollViewClass: scrollViewClass
        ),
        hasRemainingForwardRange(scrollView),
        !requirePageBoundary || shouldOfferForwardPageTurn(
          for: object,
          scrollViewClass: scrollViewClass
        )
      else {
        return original(object, selector, rawDirection)
      }

      // `.next` is the page-turn direction used by VoiceOver Read All. Flutter
      // maps it to horizontal scroll-left, so send `.up` to the hidden native
      // scroll view instead. Flutter maps `.up` to SemanticsAction.scrollDown.
      return scrollView.accessibilityScroll(.up)
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func shouldOfferForwardPageTurn(
    for object: AnyObject,
    scrollViewClass: AnyClass
  ) -> Bool {
    guard
      UIAccessibility.isVoiceOverRunning,
      Thread.isMainThread,
      let element = object as? UIAccessibilityElement,
      element.isAccessibilityElement,
      let scrollView = nearestVerticalFlutterScrollView(
        for: object,
        scrollViewClass: scrollViewClass
      ),
      hasRemainingForwardRange(scrollView),
      let viewport = screenFrame(of: scrollView),
      let owner = semanticsObject(of: scrollView),
      let itemFrame = validFrame(of: element),
      viewport.intersects(itemFrame)
    else {
      return false
    }

    var readableElements: [UIAccessibilityElement] = []
    collectVisibleReadableElements(
      from: owner,
      viewport: viewport,
      into: &readableElements
    )

    guard let last = readableElements.last else {
      return false
    }

    // UIKit's actual accessibility order, not visual bottom-edge geometry,
    // decides where Read All reaches the end of the current semantic page.
    return last === element
  }

  private static func collectVisibleReadableElements(
    from semanticsObject: NSObject,
    viewport: CGRect,
    into result: inout [UIAccessibilityElement]
  ) {
    if
      let native = nativeAccessibility(of: semanticsObject),
      let element = native as? UIAccessibilityElement,
      element.isAccessibilityElement,
      let frame = validFrame(of: element),
      viewport.intersects(frame)
    {
      result.append(element)
    }

    for child in semanticChildren(of: semanticsObject) {
      collectVisibleReadableElements(
        from: child,
        viewport: viewport,
        into: &result
      )
    }
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

  private static func nativeAccessibility(of object: NSObject) -> AnyObject? {
    let selector = NSSelectorFromString("nativeAccessibility")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "nativeAccessibility") as AnyObject?
  }

  private static func semanticsObject(of object: NSObject) -> NSObject? {
    let selector = NSSelectorFromString("semanticsObject")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "semanticsObject") as? NSObject
  }

  private static func hasRemainingForwardRange(_ scrollView: UIScrollView) -> Bool {
    guard scrollView.contentSize.height > scrollView.bounds.height + 1 else {
      return false
    }
    let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
    return scrollView.contentOffset.y < maxOffset - 1
  }

  private static func nearestVerticalFlutterScrollView(
    for object: AnyObject,
    scrollViewClass: AnyClass
  ) -> UIScrollView? {
    guard Thread.isMainThread else {
      return nil
    }

    let itemFrame: CGRect?
    if let view = object as? UIView {
      // `FlutterSemanticsScrollView` itself comes through this path. Its own
      // frame is the most precise locator and avoids choosing a nested list.
      itemFrame = screenFrame(of: view)
    } else if
      let wrapper = object as? NSObject,
      let wrappedSemantics = semanticsObject(of: wrapper),
      let native = nativeAccessibility(of: wrappedSemantics)
    {
      // `SemanticsObjectContainer.accessibilityFrame` intentionally covers the
      // whole screen in Flutter. Resolve its wrapped semantics object instead,
      // otherwise a nested scroll view could incorrectly win the size test.
      if let element = native as? UIAccessibilityElement {
        itemFrame = validFrame(of: element)
      } else if let view = native as? UIView {
        itemFrame = screenFrame(of: view)
      } else {
        itemFrame = nil
      }
    } else if let element = object as? UIAccessibilityElement {
      itemFrame = validFrame(of: element)
    } else if
      let semanticObject = object as? NSObject,
      let native = nativeAccessibility(of: semanticObject)
    {
      if let element = native as? UIAccessibilityElement {
        itemFrame = validFrame(of: element)
      } else if let view = native as? UIView {
        itemFrame = screenFrame(of: view)
      } else {
        itemFrame = nil
      }
    } else {
      itemFrame = nil
    }

    var candidates: [(view: UIScrollView, frame: CGRect)] = []
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where !window.isHidden {
        collectFlutterScrollViews(
          in: window,
          scrollViewClass: scrollViewClass,
          itemFrame: itemFrame,
          into: &candidates
        )
      }
    }

    guard !candidates.isEmpty else {
      return nil
    }

    if itemFrame == nil {
      return candidates
        .filter { hasRemainingForwardRange($0.view) }
        .min {
          ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }?.view
    }

    // For nested lists, the smallest viewport containing/intersecting the
    // semantic element is the nearest scrollable in the accessibility tree.
    return candidates.min {
      ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
    }?.view
  }

  private static func collectFlutterScrollViews(
    in view: UIView,
    scrollViewClass: AnyClass,
    itemFrame: CGRect?,
    into candidates: inout [(view: UIScrollView, frame: CGRect)]
  ) {
    if
      view.isKind(of: scrollViewClass),
      let scrollView = view as? UIScrollView,
      scrollView.contentSize.height > scrollView.bounds.height + 1,
      let frame = screenFrame(of: scrollView),
      itemFrame.map({ frame.intersects($0) }) ?? true
    {
      candidates.append((scrollView, frame))
    }

    for child in view.subviews {
      collectFlutterScrollViews(
        in: child,
        scrollViewClass: scrollViewClass,
        itemFrame: itemFrame,
        into: &candidates
      )
    }
  }

  private static func validFrame(of element: UIAccessibilityElement) -> CGRect? {
    let frame = element.accessibilityFrame
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
    VoiceOverContinuousReadPatch.install()
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
