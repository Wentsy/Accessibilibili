import Flutter
import ObjectiveC.runtime
import UIKit

/// Supplies the native reading contracts that Flutter 3.47.1 does not expose
/// for its individual semantic text elements.
///
/// The normal Flutter accessibility traversal stays authoritative. This bridge
/// does not enumerate ahead, move VoiceOver focus, poll focus, or call
/// `showOnScreen`. It only:
///
/// 1. Lets plain Flutter static-text semantics participate in
///    UIAccessibilityReadingContent.
/// 2. On iOS 18+, links adjacent static-text semantics in the same vertical
///    Flutter scrollable using Apple's text-navigation element APIs.
/// 3. Marks only the last readable static-text semantic currently exposed by a
///    vertical Flutter scrollable as `causesPageTurn`, and translates the
///    resulting `.next` page request into Flutter's vertical forward scroll.
///
/// This deliberately avoids controls such as buttons, links, sliders, FABs,
/// and bottom navigation items so ordinary left/right VoiceOver navigation is
/// not repurposed as reading navigation.
private enum VoiceOverReadAllBridge {
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

  private static let traitsSelector = NSSelectorFromString(
    "accessibilityTraits"
  )
  private static var originalTraitsGetter: TraitsGetter?

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let semanticClass = NSClassFromString("FlutterSemanticsObject"),
      let semanticsBaseClass = NSClassFromString("SemanticsObject"),
      let readingContentProtocol = NSProtocolFromString(
        "UIAccessibilityReadingContent"
      )
    else {
      return
    }

    // Capture Flutter's unmodified traits getter first. Reading-candidate
    // checks use it so the page-turn trait we add below can never recursively
    // influence eligibility.
    installPageTurnTrait(on: semanticClass)

    installReadingContent(
      on: semanticClass,
      protocolObject: readingContentProtocol
    )

    if #available(iOS 18.0, *) {
      installTextNavigationLinks(on: semanticClass)
    }

    installForwardPageTurn(on: semanticsBaseClass)
  }()

  // MARK: - UIAccessibilityReadingContent

  private static func installReadingContent(
    on targetClass: AnyClass,
    protocolObject: Protocol
  ) {
    _ = class_addProtocol(targetClass, protocolObject)

    let lineNumberSelector = NSSelectorFromString(
      "accessibilityLineNumberForPoint:"
    )
    let lineNumberBlock: @convention(block) (
      AnyObject,
      CGPoint
    ) -> Int = { object, _ in
      return readingText(of: object) == nil ? NSNotFound : 0
    }
    addRequiredProtocolMethod(
      to: targetClass,
      protocolObject: protocolObject,
      selector: lineNumberSelector,
      implementation: imp_implementationWithBlock(lineNumberBlock)
    )

    let lineContentSelector = NSSelectorFromString(
      "accessibilityContentForLineNumber:"
    )
    let lineContentBlock: @convention(block) (
      AnyObject,
      Int
    ) -> NSString? = { object, lineNumber in
      guard lineNumber == 0 else { return nil }
      return readingText(of: object)
    }
    addRequiredProtocolMethod(
      to: targetClass,
      protocolObject: protocolObject,
      selector: lineContentSelector,
      implementation: imp_implementationWithBlock(lineContentBlock)
    )

    let lineFrameSelector = NSSelectorFromString(
      "accessibilityFrameForLineNumber:"
    )
    let lineFrameBlock: @convention(block) (
      AnyObject,
      Int
    ) -> CGRect = { object, lineNumber in
      guard
        lineNumber == 0,
        readingText(of: object) != nil
      else {
        return .zero
      }

      if let element = object as? UIAccessibilityElement {
        return element.accessibilityFrame
      }
      if let view = object as? UIView, let window = view.window {
        let frameInWindow = view.convert(view.bounds, to: window)
        return window.convert(frameInWindow, to: nil)
      }
      return .zero
    }
    addRequiredProtocolMethod(
      to: targetClass,
      protocolObject: protocolObject,
      selector: lineFrameSelector,
      implementation: imp_implementationWithBlock(lineFrameBlock)
    )

    let pageContentSelector = NSSelectorFromString(
      "accessibilityPageContent"
    )
    let pageContentBlock: @convention(block) (AnyObject) -> NSString? = {
      object in
      return readingText(of: object)
    }
    addRequiredProtocolMethod(
      to: targetClass,
      protocolObject: protocolObject,
      selector: pageContentSelector,
      implementation: imp_implementationWithBlock(pageContentBlock)
    )
  }

  private static func addRequiredProtocolMethod(
    to targetClass: AnyClass,
    protocolObject: Protocol,
    selector: Selector,
    implementation: IMP
  ) {
    // These methods are not implemented by Flutter 3.47.1. If a future engine
    // supplies one itself, leave Flutter's implementation alone.
    guard class_getInstanceMethod(targetClass, selector) == nil else {
      return
    }

    let description = protocol_getMethodDescription(
      protocolObject,
      selector,
      true,
      true
    )
    guard let types = description.types else {
      return
    }

    _ = class_addMethod(
      targetClass,
      selector,
      implementation,
      types
    )
  }

  // MARK: - iOS 18 text-navigation links

  @available(iOS 18.0, *)
  private static func installTextNavigationLinks(on targetClass: AnyClass) {
    installTextNavigationGetter(
      on: targetClass,
      selectorName: "accessibilityNextTextNavigationElement",
      delta: 1
    )
    installTextNavigationGetter(
      on: targetClass,
      selectorName: "accessibilityPreviousTextNavigationElement",
      delta: -1
    )
  }

  @available(iOS 18.0, *)
  private static func installTextNavigationGetter(
    on targetClass: AnyClass,
    selectorName: String,
    delta: Int
  ) {
    let selector = NSSelectorFromString(selectorName)
    guard
      let inheritedMethod = class_getInstanceMethod(targetClass, selector),
      let typeEncoding = method_getTypeEncoding(inheritedMethod)
    else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(inheritedMethod),
      to: ObjectGetter.self
    )

    let block: @convention(block) (AnyObject) -> AnyObject? = { object in
      if let adjacent = adjacentReadingElement(from: object, delta: delta) {
        return adjacent
      }
      return original(object, selector)
    }

    // The getter normally comes from NSObject/UIAccessibility. Add an override
    // only on FlutterSemanticsObject, never mutate UIKit's implementation.
    _ = class_addMethod(
      targetClass,
      selector,
      imp_implementationWithBlock(block),
      typeEncoding
    )
  }

  private static func adjacentReadingElement(
    from object: AnyObject,
    delta: Int
  ) -> AnyObject? {
    guard
      delta != 0,
      isReadingCandidate(object),
      let semanticObject = object as? NSObject,
      let scrollView = verticalFlutterScrollAncestor(of: semanticObject),
      let owner = semanticsObject(of: scrollView)
    else {
      return nil
    }

    var ordered: [NSObject] = []
    for child in semanticChildren(of: owner) {
      collectReadingCandidates(child, into: &ordered)
    }

    guard let index = ordered.firstIndex(where: { $0 === semanticObject }) else {
      return nil
    }

    let targetIndex = index + delta
    guard ordered.indices.contains(targetIndex) else {
      return nil
    }

    return nativeAccessibility(of: ordered[targetIndex])
  }

  private static func collectReadingCandidates(
    _ object: NSObject,
    into result: inout [NSObject]
  ) {
    if isReadingCandidate(object) {
      result.append(object)
    }
    for child in semanticChildren(of: object) {
      collectReadingCandidates(child, into: &result)
    }
  }

  // MARK: - Automatic Read All page turn

  private static func installPageTurnTrait(on semanticClass: AnyClass) {
    guard let method = class_getInstanceMethod(
      semanticClass,
      traitsSelector
    ) else {
      return
    }

    let original = unsafeBitCast(
      method_getImplementation(method),
      to: TraitsGetter.self
    )
    originalTraitsGetter = original

    let block: @convention(block) (AnyObject) -> UInt64 = { object in
      let rawTraits = original(object, traitsSelector)
      guard pageTurnScrollView(for: object) != nil else {
        return rawTraits
      }

      var traits = UIAccessibilityTraits(rawValue: rawTraits)
      traits.insert(.causesPageTurn)
      return traits.rawValue
    }

    method_setImplementation(
      method,
      imp_implementationWithBlock(block)
    )
  }

  private static func installForwardPageTurn(on semanticsBaseClass: AnyClass) {
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
        let direction = UIAccessibilityScrollDirection(
          rawValue: rawDirection
        ),
        direction == .next,
        let scrollView = pageTurnScrollView(for: object)
      else {
        return original(object, selector, rawDirection)
      }

      // Flutter 3.47.1 maps `.up` to SemanticsAction.scrollDown, which moves
      // forward through a vertical list.
      let handled = scrollView.accessibilityScroll(.up)
      if handled {
        weak var weakScrollView = scrollView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
          guard
            UIAccessibility.isVoiceOverRunning,
            weakScrollView?.window != nil
          else {
            return
          }
          UIAccessibility.post(
            notification: .pageScrolled,
            argument: nil
          )
        }
      }
      return handled
    }

    method_setImplementation(
      method,
      imp_implementationWithBlock(block)
    )
  }

  /// Returns the owning vertical Flutter semantics scroll view only when
  /// `object` is the last currently exposed static-text reading element and
  /// Flutter still reports forward scroll range.
  private static func pageTurnScrollView(
    for object: AnyObject
  ) -> UIScrollView? {
    guard
      UIAccessibility.isVoiceOverRunning,
      Thread.isMainThread,
      isReadingCandidate(object),
      let semanticObject = object as? NSObject,
      let scrollView = verticalFlutterScrollAncestor(of: semanticObject),
      hasRemainingForwardRange(scrollView),
      let owner = semanticsObject(of: scrollView),
      let tail = lastReadingDescendant(ofScrollOwner: owner),
      tail === semanticObject
    else {
      return nil
    }

    return scrollView
  }

  private static func lastReadingDescendant(
    ofScrollOwner owner: NSObject
  ) -> NSObject? {
    for child in semanticChildren(of: owner).reversed() {
      if let result = lastReadingDescendant(child) {
        return result
      }
    }
    return nil
  }

  private static func lastReadingDescendant(
    _ object: NSObject
  ) -> NSObject? {
    for child in semanticChildren(of: object).reversed() {
      if let result = lastReadingDescendant(child) {
        return result
      }
    }
    return isReadingCandidate(object) ? object : nil
  }

  // MARK: - Reading eligibility

  /// Keep reading APIs away from controls. Flutter 3.47.1 reports plain leaf
  /// labels as static text; comments use that shape even though they also have
  /// tap/custom actions. Buttons, links, sliders, FABs and tabs keep their
  /// normal accessibility behavior.
  private static func isReadingCandidate(_ object: AnyObject) -> Bool {
    guard
      let semanticObject = object as? NSObject,
      isAccessibilityElement(semanticObject),
      rawReadableText(of: object) != nil,
      let originalTraitsGetter
    else {
      return false
    }

    let rawTraits = originalTraitsGetter(object, traitsSelector)
    let traits = UIAccessibilityTraits(rawValue: rawTraits)
    return traits.contains(.staticText)
  }

  private static func readingText(of object: AnyObject) -> NSString? {
    guard isReadingCandidate(object) else {
      return nil
    }
    return rawReadableText(of: object)
  }

  private static func rawReadableText(of object: AnyObject) -> NSString? {
    var parts: [String] = []

    if let element = object as? UIAccessibilityElement {
      if let label = element.accessibilityLabel?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !label.isEmpty {
        parts.append(label)
      }
      if let value = element.accessibilityValue?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !value.isEmpty, !parts.contains(value) {
        parts.append(value)
      }
    } else if let view = object as? UIView {
      if let label = view.accessibilityLabel?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !label.isEmpty {
        parts.append(label)
      }
      if let value = view.accessibilityValue?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !value.isEmpty, !parts.contains(value) {
        parts.append(value)
      }
    }

    guard !parts.isEmpty else {
      return nil
    }
    return parts.joined(separator: "，") as NSString
  }

  // MARK: - Flutter 3.47.1 semantic runtime helpers

  private static func verticalFlutterScrollAncestor(
    of semanticObject: NSObject
  ) -> UIScrollView? {
    var current: NSObject? = semanticObject

    while let node = current {
      if
        let native = nativeAccessibility(of: node),
        let scrollView = native as? UIScrollView,
        String(describing: type(of: scrollView)).contains(
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

  private static func isAccessibilityElement(_ object: NSObject) -> Bool {
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

  private static func isVerticalScrollable(_ scrollView: UIScrollView) -> Bool {
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
    VoiceOverReadAllBridge.install()
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
