import Flutter
import ObjectiveC.runtime
import UIKit

private final class VoiceOverComposerTouchProxy: UIAccessibilityElement {
  weak var target: UIAccessibilityElement?

  init(target: UIAccessibilityElement) {
    let container: Any = target.accessibilityContainer ?? target
    super.init(accessibilityContainer: container)
    self.target = target
    isAccessibilityElement = true
    accessibilityLabel = target.accessibilityLabel
    accessibilityHint = target.accessibilityHint
    accessibilityValue = target.accessibilityValue
    accessibilityTraits = target.accessibilityTraits
    accessibilityFrame = target.accessibilityFrame
  }

  override func accessibilityActivate() -> Bool {
    target?.accessibilityActivate() ?? false
  }
}

/// Gives direct VoiceOver touch one narrow escape hatch for the floating
/// "發表評論" controls without changing Flutter's normal swipe traversal or
/// the Read All/page-turn bridge below.
///
/// The marked composer remains in Flutter's semantic tree so its real frame and
/// tap action stay current. While VoiceOver is running it is hidden from normal
/// linear accessibility traversal. FlutterView and its native semantics scroll
/// views expose a temporary proxy only inside the marked composer's screen frame.
private enum VoiceOverComposerTouchBridge {
  private static let composerIdentifier = "a11y-touch-only|publish-comment"
  private static let replyComposerIdentifier = "a11y-touch-only|publish-reply"
  private static var lastProxy: VoiceOverComposerTouchProxy?

  private typealias BoolGetter = @convention(c) (
    AnyObject,
    Selector
  ) -> Bool

  private typealias HitTestHandler = @convention(c) (
    AnyObject,
    Selector,
    CGPoint,
    AnyObject?
  ) -> AnyObject?

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let semanticClass = NSClassFromString("FlutterSemanticsObject"),
      let flutterViewClass = NSClassFromString("FlutterView")
    else {
      return
    }

    installLinearTraversalExclusion(on: semanticClass)
    installFlutterViewDirectTouch(on: flutterViewClass)
    if let scrollClass = NSClassFromString("FlutterSemanticsScrollView") {
      installFlutterViewDirectTouch(on: scrollClass)
    }
  }()

  private static func installLinearTraversalExclusion(on targetClass: AnyClass) {
    let selector = NSSelectorFromString("isAccessibilityElement")
    guard
      let inheritedMethod = class_getInstanceMethod(targetClass, selector),
      let typeEncoding = method_getTypeEncoding(inheritedMethod)
    else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(inheritedMethod),
      to: BoolGetter.self
    )

    let block: @convention(block) (AnyObject) -> Bool = { object in
      if UIAccessibility.isVoiceOverRunning && isMarkedComposer(object) {
        return false
      }
      return original(object, selector)
    }

    // FlutterSemanticsObject inherits this method from SemanticsObject in the
    // engine version used by the app. Add a class-local override only; never
    // replace SemanticsObject/NSObject globally.
    _ = class_addMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(block),
      typeEncoding
    )
  }

  private static func installFlutterViewDirectTouch(on targetClass: AnyClass) {
    let selector = NSSelectorFromString("_accessibilityHitTest:withEvent:")
    guard
      let inheritedMethod = class_getInstanceMethod(targetClass, selector),
      let typeEncoding = method_getTypeEncoding(inheritedMethod)
    else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(inheritedMethod),
      to: HitTestHandler.self
    )

    let block: @convention(block) (
      AnyObject,
      CGPoint,
      AnyObject?
    ) -> AnyObject? = { object, point, event in
      guard UIAccessibility.isVoiceOverRunning else {
        return original(object, selector, point, event)
      }

      if
        let view = object as? UIView,
        let flutterView = composerSearchView(for: view, at: point),
        let composer = markedComposer(at: point, in: flutterView)
      {
        let proxy = VoiceOverComposerTouchProxy(target: composer)
        lastProxy = proxy
        return proxy
      }

      return original(object, selector, point, event)
    }

    // Both classes inherit this selector in Flutter 3.47.1. In particular,
    // FlutterSemanticsScrollView inherits UIScrollView's implementation rather
    // than SemanticsObject's hit test. Override only the concrete Flutter class;
    // preserve the captured UIKit implementation for every non-composer touch.
    _ = class_addMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(block),
      typeEncoding
    )
  }

  private static func composerSearchView(
    for view: UIView,
    at screenPoint: CGPoint
  ) -> UIView? {
    guard NSStringFromClass(type(of: view)).hasSuffix("FlutterSemanticsScrollView")
    else {
      return view
    }

    // UIKit can hit-test a native scroll view directly, bypassing FlutterView.
    // Limit this path to a vertical comment viewport at the touched location.
    // Do not alter its frame, content size, scrolling actions or page-turn traits.
    guard
      let scrollView = view as? UIScrollView,
      scrollView.contentSize.height > scrollView.bounds.height,
      scrollView.accessibilityFrame.contains(screenPoint),
      let owner = objectValue(of: scrollView, selectorName: "semanticsObject") as? NSObject,
      containsReadingReply(owner)
    else {
      return nil
    }

    var ancestor = view.superview
    while let candidate = ancestor {
      if NSStringFromClass(type(of: candidate)).hasSuffix("FlutterView") {
        return candidate
      }
      ancestor = candidate.superview
    }
    return nil
  }

  private static func containsReadingReply(_ object: NSObject) -> Bool {
    if
      let element = nativeAccessibility(of: object) as? UIAccessibilityElement,
      element.accessibilityIdentifier?.hasPrefix("a11y-read-reply|") == true
    {
      return true
    }
    return semanticChildrenInHitTestOrder(of: object).contains {
      containsReadingReply($0)
    }
  }

  private static func markedComposer(
    at point: CGPoint,
    in flutterView: UIView
  ) -> UIAccessibilityElement? {
    guard let accessibilityRoots = flutterView.accessibilityElements else {
      return nil
    }

    for root in accessibilityRoots {
      guard let rootObject = root as? NSObject else { continue }
      let semanticRoot: NSObject
      if
        NSStringFromClass(type(of: rootObject)).hasSuffix(
          "SemanticsObjectContainer"
        ),
        let owner = objectValue(
          of: rootObject,
          selectorName: "semanticsObject"
        ) as? NSObject
      {
        semanticRoot = owner
      } else {
        semanticRoot = rootObject
      }

      if let composer = findMarkedComposer(at: point, in: semanticRoot) {
        return composer
      }
    }
    return nil
  }

  private static func findMarkedComposer(
    at point: CGPoint,
    in object: NSObject
  ) -> UIAccessibilityElement? {
    // Mirror Flutter's direct-touch ordering so a currently presented route or
    // sheet wins over semantics behind it.
    for child in semanticChildrenInHitTestOrder(of: object) {
      if let hit = findMarkedComposer(at: point, in: child) {
        return hit
      }
    }

    guard
      let native = nativeAccessibility(of: object) as? UIAccessibilityElement,
      isMarkedComposer(native),
      CGRectContainsPoint(native.accessibilityFrame, point)
    else {
      return nil
    }
    return native
  }

  private static func isMarkedComposer(_ object: AnyObject?) -> Bool {
    guard
      let element = object as? UIAccessibilityElement,
      let identifier = element.accessibilityIdentifier
    else {
      return false
    }
    return identifier == composerIdentifier || identifier == replyComposerIdentifier
  }

  private static func semanticChildrenInHitTestOrder(
    of object: NSObject
  ) -> [NSObject] {
    if
      let value = objectValue(
        of: object,
        selectorName: "childrenInHitTestOrder"
      ) as? NSArray
    {
      return value.compactMap { $0 as? NSObject }
    }

    if
      let value = objectValue(of: object, selectorName: "children") as? NSArray
    {
      return value.compactMap { $0 as? NSObject }
    }
    return []
  }

  private static func nativeAccessibility(of object: NSObject) -> AnyObject? {
    objectValue(of: object, selectorName: "nativeAccessibility")
  }

  private static func objectValue(
    of object: NSObject,
    selectorName: String
  ) -> AnyObject? {
    let selector = NSSelectorFromString(selectorName)
    guard
      object.responds(to: selector),
      let result = object.perform(selector)
    else {
      return nil
    }
    return result.takeUnretainedValue()
  }
}

/// Keeps ordinary Flutter accessibility traversal untouched while giving
/// VoiceOver's text-reading path a separate chain made only from reply text.
///
/// Reply semantics opt into this bridge with the `a11y-read-reply|...`
/// identifier. On iOS 18+, adjacent reply elements are linked through Apple's
/// text-navigation element APIs. The last currently exposed reply in the
/// Flutter scrollable gets `causesPageTurn`; only the resulting `.next` page
/// request is translated to Flutter's vertical forward scroll action.
///
/// This deliberately does not hook accessibility container enumeration,
/// focus callbacks, hit testing, or showOnScreen, so normal left/right VoiceOver
/// navigation remains owned by Flutter.
private enum VoiceOverReplyReadingBridge {
  private static let replyIdentifierPrefix = "a11y-read-reply|"

  private typealias TraitsGetter = @convention(c) (
    AnyObject,
    Selector
  ) -> UInt64

  private typealias ScrollHandler = @convention(c) (
    AnyObject,
    Selector,
    Int
  ) -> Bool

  private typealias ObjectGetter = @convention(c) (
    AnyObject,
    Selector
  ) -> AnyObject?

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let semanticClass = NSClassFromString("FlutterSemanticsObject"),
      let semanticsBaseClass = NSClassFromString("SemanticsObject")
    else {
      return
    }

    if #available(iOS 18.0, *) {
      installTextNavigationGetter(
        on: semanticClass,
        selectorName: "accessibilityNextTextNavigationElement",
        delta: 1
      )
      installTextNavigationGetter(
        on: semanticClass,
        selectorName: "accessibilityPreviousTextNavigationElement",
        delta: -1
      )
    }

    installPageTurnTrait(on: semanticClass)
    installPageTurnScroll(on: semanticsBaseClass)
  }()

  // MARK: - Reading-only text links

  @available(iOS 18.0, *)
  private static func installTextNavigationGetter(
    on targetClass: AnyClass,
    selectorName: String,
    delta: Int
  ) {
    let selector = NSSelectorFromString(selectorName)
    let inheritedMethod = class_getInstanceMethod(targetClass, selector)
    let original: ObjectGetter? = inheritedMethod.map {
      unsafeBitCast(method_getImplementation($0), to: ObjectGetter.self)
    }

    let fallbackTypes = ("@@:" as NSString).utf8String
    guard let typeEncoding = inheritedMethod.flatMap(method_getTypeEncoding)
      ?? fallbackTypes
    else {
      return
    }

    let block: @convention(block) (AnyObject) -> AnyObject? = { object in
      if
        isReadingReply(object),
        let adjacent = adjacentReadingReply(from: object, delta: delta)
      {
        return adjacent
      }
      return original?(object, selector)
    }

    // FlutterSemanticsObject inherits these getters. Add a narrow override on
    // Flutter's class only; never mutate NSObject/UIKit implementations.
    _ = class_addMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(block),
      typeEncoding
    )
  }

  // MARK: - Automatic page turn at the end of the reply reading chain

  private static func installPageTurnTrait(on targetClass: AnyClass) {
    let selector = NSSelectorFromString("accessibilityTraits")
    guard let method = class_getInstanceMethod(targetClass, selector) else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: TraitsGetter.self
    )

    let block: @convention(block) (AnyObject) -> UInt64 = { object in
      let rawTraits = original(object, selector)
      guard shouldCauseForwardPageTurn(object) else {
        return rawTraits
      }

      var traits = UIAccessibilityTraits(rawValue: rawTraits)
      traits.insert(.causesPageTurn)
      return traits.rawValue
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func installPageTurnScroll(on targetClass: AnyClass) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard let method = class_getInstanceMethod(targetClass, selector) else {
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
        isReadingReply(object),
        let direction = UIAccessibilityScrollDirection(rawValue: rawDirection)
      else {
        return original(object, selector, rawDirection)
      }

      if
        direction == .next,
        shouldCauseForwardPageTurn(object),
        let ancestor = verticalScrollAncestor(of: object)
      {
        if !hasForwardRange(ancestor.scrollView),
           let wrapper = replyPageWrapper(from: ancestor.semanticObject),
           let method = class_getInstanceMethod(type(of: wrapper), selector) {
          // The list is only temporarily at its loaded boundary. Dispatch to
          // Dart's wrapper, which joins/retries the pending page request and
          // posts pageScrolled only after new comments have been laid out.
          let dispatch = unsafeBitCast(method_getImplementation(method), to: ScrollHandler.self)
          // UIKit down maps to Flutter scrollUp: the wrapper's forward action.
          return dispatch(wrapper, selector, UIAccessibilityScrollDirection.down.rawValue)
        }
        // Flutter maps UIAccessibilityScrollDirection.up to
        // SemanticsAction.scrollDown, i.e. forward through a vertical list.
        let didScroll = original(
          ancestor.semanticObject,
          selector,
          UIAccessibilityScrollDirection.up.rawValue
        )
        if didScroll {
          postPageScrolledAfterSemanticsRefresh()
        }
        return didScroll
      }

      if
        direction == .previous,
        isFirstReadingReply(object),
        let ancestor = verticalScrollAncestor(of: object),
        ancestor.scrollView.contentOffset.y > 1
      {
        let didScroll = original(
          ancestor.semanticObject,
          selector,
          UIAccessibilityScrollDirection.down.rawValue
        )
        if didScroll {
          postPageScrolledAfterSemanticsRefresh()
        }
        return didScroll
      }

      return original(object, selector, rawDirection)
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func postPageScrolledAfterSemanticsRefresh() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      guard UIAccessibility.isVoiceOverRunning else { return }
      UIAccessibility.post(notification: .pageScrolled, argument: nil)
    }
  }

  // MARK: - Reply reading chain

  private static func isReadingReply(_ object: AnyObject) -> Bool {
    guard
      let element = object as? UIAccessibilityElement,
      let identifier = element.accessibilityIdentifier,
      identifier.hasPrefix(replyIdentifierPrefix),
      let label = element.accessibilityLabel,
      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return false
    }
    return true
  }

  private static func readingGroup(of object: AnyObject) -> String? {
    guard
      let element = object as? UIAccessibilityElement,
      let identifier = element.accessibilityIdentifier,
      identifier.hasPrefix(replyIdentifierPrefix)
    else {
      return nil
    }

    let parts = identifier.split(separator: "|", omittingEmptySubsequences: false)
    guard parts.count >= 3 else {
      return nil
    }
    return "\(parts[0])|\(parts[1])|"
  }

  private static func adjacentReadingReply(
    from object: AnyObject,
    delta: Int
  ) -> AnyObject? {
    guard
      delta != 0,
      let semanticObject = object as? NSObject,
      let group = readingGroup(of: object),
      let ancestor = verticalScrollAncestor(of: object)
    else {
      return nil
    }

    let ordered = readingReplies(
      under: ancestor.semanticObject,
      group: group
    )
    guard let index = ordered.firstIndex(where: { $0 === semanticObject }) else {
      return nil
    }

    let target = index + delta
    guard ordered.indices.contains(target) else {
      return nil
    }
    return nativeAccessibility(of: ordered[target])
  }

  private static func shouldCauseForwardPageTurn(_ object: AnyObject) -> Bool {
    guard
      UIAccessibility.isVoiceOverRunning,
      let semanticObject = object as? NSObject,
      let group = readingGroup(of: object),
      let ancestor = verticalScrollAncestor(of: object)
    else {
      return false
    }

    // Traits are queried during ordinary swipe navigation too. Do not build
    // the entire reading chain for every queried element: at a loaded edge
    // the recovery marker keeps this path active even without scroll range.
    guard lastReadingReply(
      under: ancestor.semanticObject,
      group: group
    ) === semanticObject else {
      return false
    }
    // Only the boundary reply needs the range / more-page ancestor check.
    return hasForwardRange(ancestor.scrollView) ||
      replyPageWrapper(from: ancestor.semanticObject) != nil
  }

  private static func lastReadingReply(
    under root: NSObject,
    group: String
  ) -> NSObject? {
    // collectReadingReplies uses parent-before-children traversal. Its last
    // match is therefore the first match in reversed children-before-parent
    // traversal, including when a reply has nested semantic descendants.
    for child in semanticChildren(of: root).reversed() {
      if let match = lastReadingReply(under: child, group: group) {
        return match
      }
    }
    if
      let native = nativeAccessibility(of: root),
      let element = native as? UIAccessibilityElement,
      let identifier = element.accessibilityIdentifier,
      identifier.hasPrefix(group),
      isReadingReply(native)
    {
      return root
    }
    return nil
  }

  private static func isFirstReadingReply(_ object: AnyObject) -> Bool {
    guard
      let semanticObject = object as? NSObject,
      let group = readingGroup(of: object),
      let ancestor = verticalScrollAncestor(of: object)
    else {
      return false
    }

    let ordered = readingReplies(
      under: ancestor.semanticObject,
      group: group
    )
    return ordered.first === semanticObject
  }

  private static func readingReplies(
    under root: NSObject,
    group: String
  ) -> [NSObject] {
    var result: [NSObject] = []
    collectReadingReplies(root, group: group, into: &result)
    return result
  }

  private static func collectReadingReplies(
    _ object: NSObject,
    group: String,
    into result: inout [NSObject]
  ) {
    if
      let native = nativeAccessibility(of: object),
      let element = native as? UIAccessibilityElement,
      let identifier = element.accessibilityIdentifier,
      identifier.hasPrefix(group),
      isReadingReply(native)
    {
      result.append(object)
    }

    for child in semanticChildren(of: object) {
      collectReadingReplies(child, group: group, into: &result)
    }
  }

  // MARK: - Flutter semantic ancestry

  private static func verticalScrollAncestor(
    of object: AnyObject
  ) -> (semanticObject: NSObject, scrollView: UIScrollView)? {
    guard let semanticObject = object as? NSObject else {
      return nil
    }

    var current = semanticParent(of: semanticObject)
    while let candidate = current {
      if
        let native = nativeAccessibility(of: candidate) as? UIScrollView,
        NSStringFromClass(type(of: native)).hasSuffix("FlutterSemanticsScrollView")
      {
        return (candidate, native)
      }
      current = semanticParent(of: candidate)
    }
    return nil
  }

  private static func hasForwardRange(_ scrollView: UIScrollView) -> Bool {
    let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
    return scrollView.contentOffset.y < maxOffset - 1
  }

  private static func replyPageWrapper(from object: NSObject) -> NSObject? {
    var current: NSObject? = object
    for _ in 0..<64 {
      guard let candidate = current else { return nil }
      if let element = nativeAccessibility(of: candidate) as? UIAccessibilityElement,
         element.accessibilityIdentifier == "a11y-reply-scroll|more" {
        return candidate
      }
      current = semanticParent(of: candidate)
    }
    return nil
  }

  private static func semanticParent(of object: NSObject) -> NSObject? {
    objectValue(of: object, selectorName: "parent") as? NSObject
  }

  private static func semanticChildren(of object: NSObject) -> [NSObject] {
    guard
      let value = objectValue(of: object, selectorName: "children") as? NSArray
    else {
      return []
    }
    return value.compactMap { $0 as? NSObject }
  }

  private static func nativeAccessibility(of object: NSObject) -> AnyObject? {
    objectValue(of: object, selectorName: "nativeAccessibility")
  }

  private static func objectValue(
    of object: NSObject,
    selectorName: String
  ) -> AnyObject? {
    let selector = NSSelectorFromString(selectorName)
    guard
      object.responds(to: selector),
      let result = object.perform(selector)
    else {
      return nil
    }
    return result.takeUnretainedValue()
  }
}

/// Feed-only gesture routing. Flutter's inner scroll semantics can consume a
/// page gesture (or reject it at an edge) before the outer Dart Semantics node
/// receives it. Route explicit vertical gestures to the marked feed wrapper,
/// which owns paging and edge refresh. No focus, traversal or Read All hooks.
private enum VoiceOverFeedScrollBridge {
  private typealias ScrollHandler = @convention(c) (
    AnyObject, Selector, Int
  ) -> Bool

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    // Both paths are needed: Flutter semantic elements and UIKit's separate
    // FlutterSemanticsScrollView can receive accessibilityScroll directly.
    for name in [
      "SemanticsObject",
      "FlutterScrollableSemanticsObject",
      "FlutterSemanticsScrollView"
    ] {
      if let targetClass = NSClassFromString(name) {
        installScroll(on: targetClass)
      }
    }
  }()

  private static func installScroll(on targetClass: AnyClass) {
    let selector = NSSelectorFromString("accessibilityScroll:")
    guard
      let method = class_getInstanceMethod(targetClass, selector),
      let types = method_getTypeEncoding(method)
    else { return }
    let original = unsafeBitCast(method_getImplementation(method), to: ScrollHandler.self)
    let block: @convention(block) (AnyObject, Int) -> Bool = { object, rawDirection in
      guard
        UIAccessibility.isVoiceOverRunning,
        let direction = UIAccessibilityScrollDirection(rawValue: rawDirection),
        direction == .up || direction == .down,
        let receiver = object as? NSObject,
        let target = feedWrapper(from: receiver),
        target !== receiver,
        let targetMethod = class_getInstanceMethod(type(of: target), selector)
      else {
        return original(object, selector, rawDirection)
      }
      let dispatch = unsafeBitCast(
        method_getImplementation(targetMethod), to: ScrollHandler.self
      )
      // The wrapper itself falls through to Flutter's original implementation,
      // dispatching its always-present scrollUp/scrollDown action to Dart.
      return dispatch(target, selector, rawDirection)
    }
    // Add/replace only on this concrete class; never mutate UIScrollView's
    // inherited method, which would affect native editors and other controls.
    class_replaceMethod(targetClass, selector, imp_implementationWithBlock(block), types)
  }

  private static func feedWrapper(from receiver: NSObject) -> NSObject? {
    var current = objectValue(receiver, "semanticsObject") as? NSObject ?? receiver
    var seen = Set<ObjectIdentifier>()
    for _ in 0..<64 {
      guard seen.insert(ObjectIdentifier(current)).inserted else { return nil }
      let native = objectValue(current, "nativeAccessibility") ?? current
      if let element = native as? UIAccessibilityElement,
         element.accessibilityIdentifier?.hasPrefix("a11y-feed-scroll|") == true {
        return current
      }
      guard let parent = objectValue(current, "parent") as? NSObject else { return nil }
      current = parent
    }
    return nil
  }

  private static func objectValue(_ object: NSObject, _ name: String) -> AnyObject? {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector), let result = object.perform(selector) else {
      return nil
    }
    return result.takeUnretainedValue()
  }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    VoiceOverComposerTouchBridge.install()
    VoiceOverReplyReadingBridge.install()
    VoiceOverFeedScrollBridge.install()
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
