import Flutter
import ObjectiveC.runtime
import UIKit

/// Bridges VoiceOver Read All across Flutter lazy vertical lists while leaving
/// ordinary accessibility traversal untouched.
///
/// Flutter 3.47.1 already knows how to reveal an off-screen semantic node when
/// VoiceOver swipe-navigation focuses it, but Read All can consume the cached
/// semantic nodes without taking that swipe-to-focus path. Apple documents a
/// separate continuous-reading contract for paged readable content:
/// UIAccessibilityReadingContent + causesPageTurn + accessibilityScroll.
///
/// This patch supplies that reading-content contract to ordinary Flutter
/// semantic elements, marks only the final *readable* semantic descendant of a
/// vertical Flutter scrollable as a page-turn boundary, and translates the
/// resulting forward page-turn request into Flutter's existing vertical
/// accessibility scroll action. It does not enumerate ahead, move focus, poll
/// VoiceOver, or call showOnScreen on behalf of normal left/right navigation.
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

    installReadingContent(
      on: semanticClass,
      protocolObject: readingContentProtocol
    )
    installPageTurnTrait(on: semanticClass)
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
      return readableText(of: object) == nil ? NSNotFound : 0
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
      return readableText(of: object)
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
      guard lineNumber == 0 else { return .zero }
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
      return readableText(of: object)
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

  private static func readableText(of object: AnyObject) -> NSString? {
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

  // MARK: - Automatic Read All page turn

  private static func installPageTurnTrait(on semanticClass: AnyClass) {
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
        direction == .next || direction == .right,
        let scrollView = pageTurnScrollView(for: object)
      else {
        return original(object, selector, rawDirection)
      }

      // Flutter's iOS bridge maps `.up` to SemanticsAction.scrollDown, i.e.
      // move forward through a vertical list.
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
  /// `object` is the final readable semantic descendant in its currently
  /// exposed semantic subtree and there is still content below the viewport.
  private static func pageTurnScrollView(
    for object: AnyObject
  ) -> UIScrollView? {
    guard
      UIAccessibility.isVoiceOverRunning,
      Thread.isMainThread,
      readableText(of: object) != nil,
      let semanticObject = object as? NSObject,
      let scrollView = verticalFlutterScrollAncestor(of: semanticObject),
      hasRemainingForwardRange(scrollView),
      let owner = semanticsObject(of: scrollView),
      let tail = lastReadableDescendant(ofScrollOwner: owner),
      tail === semanticObject
    else {
      return nil
    }

    return scrollView
  }

  private static func lastReadableDescendant(
    ofScrollOwner owner: NSObject
  ) -> NSObject? {
    for child in semanticChildren(of: owner).reversed() {
      if let result = lastReadableDescendant(child) {
        return result
      }
    }
    return nil
  }

  private static func lastReadableDescendant(
    _ object: NSObject
  ) -> NSObject? {
    for child in semanticChildren(of: object).reversed() {
      if let result = lastReadableDescendant(child) {
        return result
      }
    }

    guard
      isAccessibilityElement(object),
      readableText(of: object) != nil
    else {
      return nil
    }
    return object
  }

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
