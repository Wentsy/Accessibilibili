import Flutter
import ObjectiveC.runtime
import UIKit

private final class TouchOnlyAccessibilityProxy: UIAccessibilityElement {
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

/// Keeps ordinary Flutter accessibility traversal untouched while giving
/// VoiceOver's text-reading path a separate chain made only from reply text.
///
/// Reply semantics opt into this bridge with the `a11y-read-reply|...`
/// identifier. On iOS 18+, adjacent reply elements are linked through Apple's
/// text-navigation element APIs. The last currently exposed reply in the
/// Flutter scrollable gets `causesPageTurn`; only the resulting `.next` page
/// request is translated to Flutter's vertical forward scroll action.
///
/// Composer actions marked `a11y-touch-only|...` stay in Flutter's semantic
/// tree so their original frame and tap action remain available, but they are
/// not exposed as ordinary accessibility elements. Flutter's existing semantic
/// hit-test is left intact; only when that hit-test actually lands on one of
/// these marked actions do we return a temporary proxy that VoiceOver can focus
/// by direct touch. This keeps swipe navigation and Read All unchanged outside
/// those explicitly marked composer controls.
private enum VoiceOverReplyReadingBridge {
  private static let replyIdentifierPrefix = "a11y-read-reply|"
  private static let touchOnlyIdentifierPrefix = "a11y-touch-only|"
  private static var lastTouchOnlyProxy: TouchOnlyAccessibilityProxy?

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
    installTouchOnlyAccessibilityElementOverride(on: semanticClass)
    installTouchOnlyHitTest(on: semanticsBaseClass)
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

    _ = class_addMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(block),
      typeEncoding
    )
  }

  // MARK: - Touch-only composer actions

  private static func installTouchOnlyAccessibilityElementOverride(
    on targetClass: AnyClass
  ) {
    let selector = NSSelectorFromString("isAccessibilityElement")
    guard let inheritedMethod = class_getInstanceMethod(targetClass, selector),
          let typeEncoding = method_getTypeEncoding(inheritedMethod)
    else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(inheritedMethod),
      to: BoolGetter.self
    )

    let block: @convention(block) (AnyObject) -> Bool = { object in
      if UIAccessibility.isVoiceOverRunning && isTouchOnlyElement(object) {
        return false
      }
      return original(object, selector)
    }

    let implementation = imp_implementationWithBlock(block)
    if !class_addMethod(targetClass, selector, implementation, typeEncoding) {
      if let ownMethod = class_getInstanceMethod(targetClass, selector) {
        method_setImplementation(ownMethod, implementation)
      }
    }
  }

  private static func installTouchOnlyHitTest(on targetClass: AnyClass) {
    let selector = NSSelectorFromString("_accessibilityHitTest:withEvent:")
    guard let method = class_getInstanceMethod(targetClass, selector) else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
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

      guard let result = original(object, selector, point, event) else {
        return nil
      }

      if result is TouchOnlyAccessibilityProxy {
        return result
      }

      guard
        let element = result as? UIAccessibilityElement,
        isTouchOnlyElement(element)
      else {
        return result
      }

      let proxy = TouchOnlyAccessibilityProxy(target: element)
      lastTouchOnlyProxy = proxy
      return proxy
    }

    method_setImplementation(method, imp_implementationWithBlock(block))
  }

  private static func isTouchOnlyElement(_ object: AnyObject?) -> Bool {
    guard
      let element = object as? UIAccessibilityElement,
      let identifier = element.accessibilityIdentifier
    else {
      return false
    }
    return identifier.hasPrefix(touchOnlyIdentifierPrefix)
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
      let ancestor = verticalScrollAncestor(of: object),
      hasForwardRange(ancestor.scrollView)
    else {
      return false
    }

    let ordered = readingReplies(
      under: ancestor.semanticObject,
      group: group
    )
    return ordered.last === semanticObject
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
        NSStringFromClass(type(of: native)).hasSuffix("FlutterSemanticsScrollView"),
        native.contentSize.height > native.bounds.height + 1
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

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    VoiceOverReplyReadingBridge.install()
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
