import Flutter
import ObjectiveC.runtime
import UIKit

/// Keeps VoiceOver Read All moving through lazy Flutter lists by borrowing the
/// same `showOnScreen` path that Flutter uses for swipe-to-focus navigation.
///
/// VoiceOver Read All only walks the semantic elements that are currently
/// exposed on screen. When it reaches the last visible child of a lazy list it
/// can fall through to unrelated siblings (bottom tabs, floating buttons, etc.)
/// instead of asking Flutter for the next list item.
///
/// Flutter's iOS engine already has the behavior we want for ordinary
/// left/right VoiceOver navigation: when an off-screen semantic item is about
/// to receive focus, `showOnScreen` scrolls it into view. This patch hooks real
/// accessibility focus changes. As soon as VoiceOver starts reading the last
/// visible semantic item inside a vertical Flutter scrollable, it proactively
/// asks the *next semantic item in Flutter's own accessibility order* to show
/// itself on screen. The current item can keep speaking while Flutter exposes
/// the following item, so Read All has another list child to continue into.
///
/// No Dart widget order, layout, cache extent, FAB placement, or comment UI is
/// changed by this patch.
private enum VoiceOverContinuousReadPatch {
  private typealias FocusHandler = @convention(c) (
    AnyObject,
    Selector
  ) -> Void
  private typealias ShowOnScreenHandler = @convention(c) (
    AnyObject,
    Selector
  ) -> Void

  private static var lastPrefetchedFocus: ObjectIdentifier?

  static func install() {
    _ = installOnce
  }

  private static let installOnce: Void = {
    guard
      let semanticsBaseClass = NSClassFromString("SemanticsObject"),
      let scrollViewClass = NSClassFromString("FlutterSemanticsScrollView")
    else {
      return
    }

    installFocusReadAheadHook(
      semanticsBaseClass: semanticsBaseClass,
      scrollViewClass: scrollViewClass
    )
  }()

  private static func installFocusReadAheadHook(
    semanticsBaseClass: AnyClass,
    scrollViewClass: AnyClass
  ) {
    let focusSelector = NSSelectorFromString(
      "accessibilityElementDidBecomeFocused"
    )
    let showSelector = NSSelectorFromString("showOnScreen")

    guard
      let focusMethod = class_getInstanceMethod(
        semanticsBaseClass,
        focusSelector
      ),
      let showMethod = class_getInstanceMethod(
        semanticsBaseClass,
        showSelector
      )
    else {
      return
    }

    let originalFocus = unsafeBitCast(
      method_getImplementation(focusMethod),
      to: FocusHandler.self
    )
    let showOnScreen = unsafeBitCast(
      method_getImplementation(showMethod),
      to: ShowOnScreenHandler.self
    )

    let block: @convention(block) (AnyObject) -> Void = { object in
      // Preserve Flutter's normal focus bookkeeping, Dart
      // onDidGainAccessibilityFocus callbacks, and existing show-on-screen
      // behavior first.
      originalFocus(object, focusSelector)

      guard UIAccessibility.isVoiceOverRunning, Thread.isMainThread else {
        return
      }

      let currentID = ObjectIdentifier(object)
      if
        let previous = lastPrefetchedFocus,
        previous != currentID
      {
        // A genuinely new VoiceOver item is being read. Allow that item to
        // become a future read-ahead boundary even if Flutter later reuses the
        // same semantic object instance elsewhere in the list.
        lastPrefetchedFocus = nil
      }

      readAheadFromFocusedItem(
        object,
        scrollViewClass: scrollViewClass,
        showSelector: showSelector,
        showOnScreen: showOnScreen
      )
    }

    method_setImplementation(
      focusMethod,
      imp_implementationWithBlock(block)
    )
  }

  private static func readAheadFromFocusedItem(
    _ focused: AnyObject,
    scrollViewClass: AnyClass,
    showSelector: Selector,
    showOnScreen: ShowOnScreenHandler
  ) {
    guard
      let focusedObject = focused as? NSObject,
      let scrollView = nearestVerticalFlutterScrollView(
        for: focused,
        scrollViewClass: scrollViewClass
      ),
      let viewport = screenFrame(of: scrollView),
      let owner = semanticsObject(of: scrollView)
    else {
      return
    }

    var orderedObjects: [NSObject] = []
    for child in semanticChildren(of: owner) {
      collectFocusableSemanticObjects(
        from: child,
        into: &orderedObjects
      )
    }

    guard
      let focusedIndex = orderedObjects.firstIndex(
        where: { $0 === focusedObject }
      )
    else {
      return
    }

    // Only act when the item VoiceOver has just started reading is the final
    // currently-visible semantic item of this Flutter scrollable. This keeps
    // ordinary focus changes elsewhere untouched and prevents premature page
    // movement in the middle of a screen.
    var lastVisibleIndex: Int?
    for (index, object) in orderedObjects.enumerated() {
      guard
        let native = nativeAccessibility(of: object),
        let frame = accessibilityFrame(of: native),
        viewport.intersects(frame)
      else {
        continue
      }
      lastVisibleIndex = index
    }

    guard lastVisibleIndex == focusedIndex else {
      return
    }

    let currentID = ObjectIdentifier(focused)
    guard lastPrefetchedFocus != currentID else {
      // Some semantics updates can re-notify focus for the same element. Do not
      // scroll repeatedly while VoiceOver is still speaking that one item.
      return
    }
    lastPrefetchedFocus = currentID

    if focusedIndex + 1 < orderedObjects.count {
      let nextObject = orderedObjects[focusedIndex + 1]

      // This is the key: use Flutter's own swipe-navigation primitive rather
      // than inventing a page turn. If the next semantic item is hidden or just
      // outside the viewport, Flutter scrolls exactly enough to expose it.
      showOnScreen(nextObject, showSelector)
      return
    }

    // A very lazy Sliver may not have created even one off-screen semantic item
    // yet. In that case there is nothing to call showOnScreen on, so request
    // one normal accessibility page scroll only as a bootstrap. Once Flutter
    // builds the next semantics batch, subsequent boundaries use showOnScreen.
    if hasRemainingForwardRange(scrollView) {
      _ = scrollView.accessibilityScroll(.up)
    }
  }

  private static func collectFocusableSemanticObjects(
    from object: NSObject,
    into result: inout [NSObject]
  ) {
    if isFocusableSemanticObject(object) {
      result.append(object)
    }

    for child in semanticChildren(of: object) {
      collectFocusableSemanticObjects(
        from: child,
        into: &result
      )
    }
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

  private static func nearestVerticalFlutterScrollView(
    for object: AnyObject,
    scrollViewClass: AnyClass
  ) -> UIScrollView? {
    guard
      Thread.isMainThread,
      let itemFrame = accessibilityFrame(of: object)
    else {
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

    // A focused item may live inside nested scrollables. Prefer the smallest
    // vertical viewport intersecting it, which is the closest semantic scroll
    // ancestor in practice.
    return candidates.min {
      ($0.frame.width * $0.frame.height) <
        ($1.frame.width * $1.frame.height)
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
      isVerticalScrollable(scrollView),
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

  private static func accessibilityFrame(
    of object: AnyObject
  ) -> CGRect? {
    if let element = object as? UIAccessibilityElement {
      return validFrame(element.accessibilityFrame)
    }
    if let view = object as? UIView {
      return screenFrame(of: view)
    }
    if
      let wrapper = object as? NSObject,
      let native = nativeAccessibility(of: wrapper),
      native !== object
    {
      return accessibilityFrame(of: native)
    }
    return nil
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
