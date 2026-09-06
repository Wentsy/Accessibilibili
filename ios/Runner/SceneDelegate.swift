import Flutter
import ObjectiveC.runtime
import UIKit

/// Bridges VoiceOver Read All across Flutter's lazy semantic cache without
/// changing any Dart widget order or layout.
///
/// Flutter keeps a small number of semantic children built beyond the visible
/// viewport. VoiceOver Read All can speak those off-screen children, so the
/// correct page boundary is not the last *visible* item. It is the last
/// currently exposed focusable semantic descendant of the vertical Flutter
/// scrollable.
///
/// Apple recommends applying `causesPageTurn` to the final readable element of
/// a page and handling `accessibilityScroll` to advance. This patch maps that
/// model onto Flutter's semantic cache: mark the actual cached tail, translate
/// VoiceOver's `.next` page request into Flutter's vertical `.up` accessibility
/// scroll, then post `.pageScrolled` so VoiceOver re-evaluates the new page.
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

  private final class WeakScrollBox {
    weak var value: UIScrollView?
  }

  private static let pendingPageTurnScroll = WeakScrollBox()

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let flutterSemanticClass = NSClassFromString("FlutterSemanticsObject"),
      let semanticsBaseClass = NSClassFromString("SemanticsObject"),
      let semanticsContainerClass = NSClassFromString("SemanticsObjectContainer"),
      let scrollViewClass = NSClassFromString("FlutterSemanticsScrollView")
    else {
      return
    }

    installTailTraitsHook(
      semanticClass: flutterSemanticClass,
      scrollViewClass: scrollViewClass
    )
    installSemanticScrollHook(
      semanticsBaseClass: semanticsBaseClass,
      scrollViewClass: scrollViewClass
    )
    installContainerScrollHook(
      containerClass: semanticsContainerClass,
      scrollViewClass: scrollViewClass
    )
    installScrollViewHook(
      scrollViewClass: scrollViewClass
    )

    if let flutterViewControllerClass = NSClassFromString("FlutterViewController") {
      installViewControllerFallback(
        viewControllerClass: flutterViewControllerClass
      )
    }
  }()

  private static func installTailTraitsHook(
    semanticClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
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
      guard
        isCurrentSemanticPageTail(
          object,
          scrollViewClass: scrollViewClass
        )
      else {
        return rawTraits
      }

      var traits = UIAccessibilityTraits(rawValue: rawTraits)
      traits.insert(.causesPageTurn)
      return traits.rawValue
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installSemanticScrollHook(
    semanticsBaseClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
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
        isCurrentSemanticPageTail(
          object,
          scrollViewClass: scrollViewClass
        ),
        let scrollView = verticalFlutterScrollAncestor(
          for: object,
          scrollViewClass: scrollViewClass
        )
      else {
        return original(object, selector, rawDirection)
      }

      return performForwardPageTurn(on: scrollView)
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installContainerScrollHook(
    containerClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard let method = class_getInstanceMethod(containerClass, selector) else {
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
        let wrapper = object as? NSObject,
        let owner = semanticsObject(of: wrapper),
        let native = nativeAccessibility(of: owner),
        let scrollView = native as? UIScrollView,
        scrollView.isKind(of: scrollViewClass),
        isVerticalScrollable(scrollView),
        hasRemainingForwardRange(scrollView)
      else {
        return original(object, selector, rawDirection)
      }

      return performForwardPageTurn(on: scrollView)
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installScrollViewHook(
    scrollViewClass: AnyClass
  ) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard let method = class_getInstanceMethod(scrollViewClass, selector) else {
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
        let scrollView = object as? UIScrollView,
        isVerticalScrollable(scrollView),
        hasRemainingForwardRange(scrollView)
      else {
        return original(object, selector, rawDirection)
      }

      let handled = original(
        object,
        selector,
        Int(UIAccessibilityScrollDirection.up.rawValue)
      )
      if handled {
        notifyPageScrolled(after: scrollView)
      }
      return handled
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installViewControllerFallback(
    viewControllerClass: AnyClass
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
        let scrollView = pendingPageTurnScroll.value,
        scrollView.window != nil,
        isVerticalScrollable(scrollView),
        hasRemainingForwardRange(scrollView)
      else {
        return original(object, selector, rawDirection)
      }

      return performForwardPageTurn(on: scrollView)
    }

    let replacement = imp_implementationWithBlock(block)

    // Prefer adding an override so an inherited UIKit implementation is not
    // mutated globally. If FlutterViewController already owns the method,
    // replace only that class's implementation.
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

  private static func isCurrentSemanticPageTail(
    _ object: AnyObject,
    scrollViewClass: AnyClass
  ) -> Bool {
    guard
      UIAccessibility.isVoiceOverRunning,
      Thread.isMainThread,
      let semanticObject = object as? NSObject,
      let scrollView = verticalFlutterScrollAncestor(
        for: semanticObject,
        scrollViewClass: scrollViewClass
      ),
      hasRemainingForwardRange(scrollView),
      let scrollOwner = semanticsObject(of: scrollView),
      let tail = lastFocusableDescendantOfScrollOwner(scrollOwner),
      tail === semanticObject
    else {
      return false
    }

    // If UIKit chooses to send the automatic page request to the page's view
    // controller (as in Apple's UIKit sample) rather than the semantic element
    // or its Flutter container, this identifies which Flutter list to advance.
    pendingPageTurnScroll.value = scrollView
    return true
  }

  private static func lastFocusableDescendantOfScrollOwner(
    _ owner: NSObject
  ) -> NSObject? {
    for child in semanticChildren(of: owner).reversed() {
      if let result = lastFocusableDescendant(child) {
        return result
      }
    }
    return nil
  }

  private static func lastFocusableDescendant(
    _ object: NSObject
  ) -> NSObject? {
    // Flutter accessibility container order is the semantic object itself,
    // followed by its children. Therefore the final readable item is found by
    // searching children in reverse before considering the parent object.
    for child in semanticChildren(of: object).reversed() {
      if let result = lastFocusableDescendant(child) {
        return result
      }
    }

    return isFocusableSemanticObject(object) ? object : nil
  }

  private static func isFocusableSemanticObject(
    _ object: NSObject
  ) -> Bool {
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

  private static func verticalFlutterScrollAncestor(
    for object: AnyObject,
    scrollViewClass: AnyClass
  ) -> UIScrollView? {
    var current: NSObject?

    if
      let wrapper = object as? NSObject,
      let wrapped = semanticsObject(of: wrapper)
    {
      current = wrapped
    } else {
      current = object as? NSObject
    }

    while let node = current {
      if
        let native = nativeAccessibility(of: node),
        let scrollView = native as? UIScrollView,
        scrollView.isKind(of: scrollViewClass),
        isVerticalScrollable(scrollView)
      {
        return scrollView
      }
      current = semanticParent(of: node)
    }

    return nil
  }

  private static func performForwardPageTurn(
    on scrollView: UIScrollView
  ) -> Bool {
    guard
      isVerticalScrollable(scrollView),
      hasRemainingForwardRange(scrollView)
    else {
      return false
    }

    // Flutter maps `.up` to SemanticsAction.scrollDown, i.e. move forward
    // through a vertical list.
    let handled = scrollView.accessibilityScroll(.up)
    if handled {
      notifyPageScrolled(after: scrollView)
    }
    return handled
  }

  private static func notifyPageScrolled(
    after scrollView: UIScrollView
  ) {
    weak var weakScrollView = scrollView
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      guard
        UIAccessibility.isVoiceOverRunning,
        weakScrollView?.window != nil
      else {
        return
      }

      // Apple's page-turn example posts pageScrolled after changing pages.
      // Supplying no string avoids adding an artificial spoken page number.
      UIAccessibility.post(notification: .pageScrolled, argument: nil)
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

  private static func semanticsObject(of object: NSObject) -> NSObject? {
    let selector = NSSelectorFromString("semanticsObject")
    guard object.responds(to: selector) else {
      return nil
    }
    return object.value(forKey: "semanticsObject") as? NSObject
  }

  private static func isVerticalScrollable(
    _ scrollView: UIScrollView
  ) -> Bool {
    scrollView.bounds.height > 1 &&
      scrollView.contentSize.height > scrollView.bounds.height + 1
  }

  private static func hasRemainingForwardRange(
    _ scrollView: UIScrollView
  ) -> Bool {
    let maxOffset = max(
      0,
      scrollView.contentSize.height - scrollView.bounds.height
    )
    return scrollView.contentOffset.y < maxOffset - 1
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
