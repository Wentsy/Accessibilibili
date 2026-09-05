import Flutter
import ObjectiveC.runtime
import UIKit

/// VoiceOver's Read All gesture uses the `causesPageTurn` trait to decide when
/// it should ask an app for the next page. Flutter exposes vertical lists as a
/// hidden native `FlutterSemanticsScrollView`, but ordinary Flutter semantic
/// children do not carry that trait and iOS' `.next` direction is mapped by
/// Flutter to horizontal scrolling.
///
/// Keep Flutter's normal semantics/focus behavior intact and only augment the
/// semantic element that currently reaches the lower edge of a vertical
/// Flutter viewport. When VoiceOver finishes reading that element, translate
/// the automatic `.next` page request into the vertical `.up` accessibility
/// scroll expected by Flutter. Swipe navigation and three-finger scrolling keep
/// using their existing paths.
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
      let scrollViewClass = NSClassFromString("FlutterSemanticsScrollView")
    else {
      return
    }

    installTraitsHook(
      semanticClass: semanticClass,
      scrollViewClass: scrollViewClass
    )
    installScrollHook(
      semanticsBaseClass: semanticsBaseClass,
      scrollViewClass: scrollViewClass
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
    semanticsBaseClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard let method = class_getInstanceMethod(semanticsBaseClass, selector) else {
      return
    }

    let originalIMP = method_getImplementation(method)
    let original = unsafeBitCast(originalIMP, to: ScrollHandler.self)

    let block: @convention(block) (AnyObject, Int) -> Bool = {
      object,
      rawDirection in
      if original(object, selector, rawDirection) {
        return true
      }

      guard
        UIAccessibility.isVoiceOverRunning,
        let direction = UIAccessibilityScrollDirection(rawValue: rawDirection),
        direction == .next,
        shouldOfferForwardPageTurn(
          for: object,
          scrollViewClass: scrollViewClass
        ),
        let scrollView = nearestVerticalFlutterScrollView(
          for: object,
          scrollViewClass: scrollViewClass
        )
      else {
        return false
      }

      // Flutter maps UIAccessibilityScrollDirection.next to horizontal
      // SemanticsAction.scrollLeft. A vertical list instead needs `.up`, which
      // Flutter correctly maps to SemanticsAction.scrollDown (content forward).
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
      let element = object as? UIAccessibilityElement,
      let scrollView = nearestVerticalFlutterScrollView(
        for: object,
        scrollViewClass: scrollViewClass
      ),
      let scrollFrame = screenFrame(of: scrollView)
    else {
      return false
    }

    let itemFrame = element.accessibilityFrame
    guard !itemFrame.isNull, !itemFrame.isInfinite else {
      return false
    }

    let visiblePart = itemFrame.intersection(scrollFrame)
    guard !visiblePart.isNull, !visiblePart.isEmpty else {
      return false
    }

    // Mark only the semantic item touching the bottom edge of this viewport.
    // This avoids turning the page after every list row while still covering
    // variable-height comments/cards and slightly clipped final rows.
    let edgeSlop = max(12, min(36, scrollFrame.height * 0.06))
    guard visiblePart.maxY >= scrollFrame.maxY - edgeSlop else {
      return false
    }

    let maxOffset = max(
      0,
      scrollView.contentSize.height - scrollView.bounds.height
    )
    return scrollView.contentOffset.y < maxOffset - 1
  }

  private static func nearestVerticalFlutterScrollView(
    for object: AnyObject,
    scrollViewClass: AnyClass
  ) -> UIScrollView? {
    guard
      Thread.isMainThread,
      let element = object as? UIAccessibilityElement
    else {
      return nil
    }

    let itemFrame = element.accessibilityFrame
    guard !itemFrame.isNull, !itemFrame.isInfinite else {
      return nil
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

    // Nested Flutter scrollables can overlap. The smallest matching viewport is
    // the closest semantic scroll container for the focused/read item.
    return candidates.min {
      ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
    }?.view
  }

  private static func collectFlutterScrollViews(
    in view: UIView,
    scrollViewClass: AnyClass,
    itemFrame: CGRect,
    into candidates: inout [(view: UIScrollView, frame: CGRect)]
  ) {
    if
      view.isKind(of: scrollViewClass),
      let scrollView = view as? UIScrollView,
      scrollView.contentSize.height > scrollView.bounds.height + 1,
      let frame = screenFrame(of: scrollView),
      frame.intersects(itemFrame)
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
