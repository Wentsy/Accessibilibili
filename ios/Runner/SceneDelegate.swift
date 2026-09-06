import Flutter
import ObjectiveC.runtime
import UIKit

/// Makes VoiceOver's Read All traverse lazy Flutter scrollables page by page
/// without changing the Dart widget/layout structure.
///
/// Flutter only exposes the currently-built semantic children of a lazy list.
/// Read All therefore reaches the end of that semantic container and then
/// continues into unrelated siblings (for example the bottom tab bar or a
/// floating "發表評論" button) instead of asking Flutter to scroll.
///
/// This patch appends one native, silent accessibility proxy to every vertical
/// Flutter semantics scroll container that still has content below it. When
/// VoiceOver reaches that proxy, it asks Flutter to scroll forward, waits for
/// the semantics tree to refresh, and moves accessibility focus to the first
/// newly-visible semantic element. The proxy then remains the final element of
/// the refreshed page, allowing the same hand-off to repeat.
private enum VoiceOverContinuousReadPatch {
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

  private static var proxyAssociationKey: UInt8 = 0

  private final class PageTurnProxy: UIAccessibilityElement {
    weak var scrollView: UIScrollView?
    var isTurningPage = false

    override func accessibilityElementDidBecomeFocused() {
      super.accessibilityElementDidBecomeFocused()
      VoiceOverContinuousReadPatch.turnPage(from: self)
    }
  }

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let semanticsContainerClass = NSClassFromString("SemanticsObjectContainer"),
      let scrollViewClass = NSClassFromString("FlutterSemanticsScrollView")
    else {
      return
    }

    installContainerProxyHooks(
      semanticsContainerClass: semanticsContainerClass,
      scrollViewClass: scrollViewClass
    )
  }()

  private static func installContainerProxyHooks(
    semanticsContainerClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
    let countSelector = NSSelectorFromString("accessibilityElementCount")
    let elementSelector = NSSelectorFromString("accessibilityElementAtIndex:")
    let indexSelector = NSSelectorFromString("indexOfAccessibilityElement:")

    guard
      let countMethod = class_getInstanceMethod(
        semanticsContainerClass,
        countSelector
      ),
      let elementMethod = class_getInstanceMethod(
        semanticsContainerClass,
        elementSelector
      ),
      let indexMethod = class_getInstanceMethod(
        semanticsContainerClass,
        indexSelector
      )
    else {
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

    let countBlock: @convention(block) (AnyObject) -> Int = { container in
      let original = originalCount(container, countSelector)
      guard
        pageTurnScrollView(
          for: container,
          scrollViewClass: scrollViewClass
        ) != nil
      else {
        return original
      }
      return original + 1
    }

    let elementBlock: @convention(block) (
      AnyObject,
      Int
    ) -> AnyObject? = { container, index in
      let originalCountValue = originalCount(container, countSelector)
      guard index == originalCountValue else {
        return originalElement(container, elementSelector, index)
      }

      guard
        let scrollView = pageTurnScrollView(
          for: container,
          scrollViewClass: scrollViewClass
        )
      else {
        return originalElement(container, elementSelector, index)
      }

      return pageTurnProxy(
        for: container,
        scrollView: scrollView
      )
    }

    let indexBlock: @convention(block) (
      AnyObject,
      AnyObject
    ) -> Int = { container, element in
      if
        let proxy = objc_getAssociatedObject(
          container,
          &proxyAssociationKey
        ) as? PageTurnProxy,
        proxy === element,
        pageTurnScrollView(
          for: container,
          scrollViewClass: scrollViewClass
        ) != nil
      {
        return originalCount(container, countSelector)
      }

      return originalIndex(container, indexSelector, element)
    }

    method_setImplementation(
      countMethod,
      imp_implementationWithBlock(countBlock)
    )
    method_setImplementation(
      elementMethod,
      imp_implementationWithBlock(elementBlock)
    )
    method_setImplementation(
      indexMethod,
      imp_implementationWithBlock(indexBlock)
    )
  }

  private static func pageTurnScrollView(
    for container: AnyObject,
    scrollViewClass: AnyClass
  ) -> UIScrollView? {
    guard
      UIAccessibility.isVoiceOverRunning,
      Thread.isMainThread,
      let wrapper = container as? NSObject,
      let owner = semanticsObject(of: wrapper),
      let native = nativeAccessibility(of: owner),
      let scrollView = native as? UIScrollView,
      scrollView.isKind(of: scrollViewClass),
      isVerticalScrollable(scrollView),
      hasRemainingForwardRange(scrollView)
    else {
      return nil
    }

    return scrollView
  }

  private static func pageTurnProxy(
    for container: AnyObject,
    scrollView: UIScrollView
  ) -> PageTurnProxy {
    if
      let existing = objc_getAssociatedObject(
        container,
        &proxyAssociationKey
      ) as? PageTurnProxy
    {
      existing.scrollView = scrollView
      configureProxy(existing, scrollView: scrollView)
      return existing
    }

    let proxy = PageTurnProxy(accessibilityContainer: container)
    proxy.scrollView = scrollView
    configureProxy(proxy, scrollView: scrollView)
    objc_setAssociatedObject(
      container,
      &proxyAssociationKey,
      proxy,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    return proxy
  }

  private static func configureProxy(
    _ proxy: PageTurnProxy,
    scrollView: UIScrollView
  ) {
    proxy.isAccessibilityElement = true

    // U+2060 WORD JOINER is intentionally non-spoken. The element needs a
    // non-empty label so VoiceOver will traverse it, but it should not add an
    // audible "next page" item to the user's reading stream.
    proxy.accessibilityLabel = "\u{2060}"
    proxy.accessibilityHint = nil
    proxy.accessibilityValue = nil
    proxy.accessibilityTraits = []

    if let viewport = screenFrame(of: scrollView) {
      proxy.accessibilityFrame = CGRect(
        x: viewport.minX + 1,
        y: max(viewport.minY + 1, viewport.maxY - 2),
        width: 1,
        height: 1
      )
    }
  }

  private static func turnPage(from proxy: PageTurnProxy) {
    guard
      UIAccessibility.isVoiceOverRunning,
      Thread.isMainThread,
      !proxy.isTurningPage,
      let scrollView = proxy.scrollView,
      isVerticalScrollable(scrollView),
      hasRemainingForwardRange(scrollView)
    else {
      return
    }

    let beforeElements = visibleReadableElements(in: scrollView)
    let beforeIDs = Set(beforeElements.map(ObjectIdentifier.init))
    let beforeOffset = scrollView.contentOffset.y

    proxy.isTurningPage = true

    // Flutter maps `.up` to SemanticsAction.scrollDown, which is forward
    // movement through a vertical list.
    guard scrollView.accessibilityScroll(.up) else {
      proxy.isTurningPage = false
      return
    }

    // Keep VoiceOver anchored to the proxy while Flutter performs the semantic
    // scroll. This prevents Read All from escaping into sibling controls before
    // the lazy list has published its next batch of semantics.
    UIAccessibility.post(notification: .layoutChanged, argument: proxy)

    waitForNextSemanticPage(
      proxy: proxy,
      scrollView: scrollView,
      beforeIDs: beforeIDs,
      beforeOffset: beforeOffset,
      attempt: 0
    )
  }

  private static func waitForNextSemanticPage(
    proxy: PageTurnProxy,
    scrollView: UIScrollView,
    beforeIDs: Set<ObjectIdentifier>,
    beforeOffset: CGFloat,
    attempt: Int
  ) {
    let delays: [TimeInterval] = [0.06, 0.10, 0.16, 0.24]
    guard attempt < delays.count else {
      proxy.isTurningPage = false
      UIAccessibility.post(notification: .layoutChanged, argument: nil)
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) {
      guard
        UIAccessibility.isVoiceOverRunning,
        proxy.isTurningPage,
        proxy.scrollView === scrollView
      else {
        proxy.isTurningPage = false
        return
      }

      let afterElements = visibleReadableElements(in: scrollView)
      let moved = scrollView.contentOffset.y > beforeOffset + 0.5
      let newElement = afterElements.first {
        !beforeIDs.contains(ObjectIdentifier($0))
      }

      if moved, let target = newElement ?? afterElements.first {
        proxy.isTurningPage = false

        // Apple documents layoutChanged with an accessibility element argument
        // as the way to move VoiceOver focus after a layout update. Focusing
        // the first newly-visible Flutter semantic item makes Read All resume
        // inside the list instead of falling through to the tab bar / FAB.
        UIAccessibility.post(notification: .layoutChanged, argument: target)
        return
      }

      waitForNextSemanticPage(
        proxy: proxy,
        scrollView: scrollView,
        beforeIDs: beforeIDs,
        beforeOffset: beforeOffset,
        attempt: attempt + 1
      )
    }
  }

  private static func visibleReadableElements(
    in scrollView: UIScrollView
  ) -> [UIAccessibilityElement] {
    guard
      let viewport = screenFrame(of: scrollView),
      let owner = semanticsObject(of: scrollView)
    else {
      return []
    }

    var result: [UIAccessibilityElement] = []
    for child in semanticChildren(of: owner) {
      collectVisibleReadableElements(
        from: child,
        viewport: viewport,
        into: &result
      )
    }
    return result
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

  private static func validFrame(
    of element: UIAccessibilityElement
  ) -> CGRect? {
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
