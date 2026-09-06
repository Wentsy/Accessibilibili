# VoiceOver Read All investigation

## 2026-09-06 finding

On iOS VoiceOver, two-finger Read All can speak several Flutter semantic items that are already built beyond the visible viewport, but it stops when that finite semantic cache is exhausted. Therefore the Read All page boundary is not the last visually visible item; it is the last currently exposed/focusable semantic descendant of the vertical Flutter scrollable.

Apple's WWDC26 session "Enhance the accessibility of your reading app" recommends applying the `causesPageTurn` trait to the last content element of a page and pairing it with `accessibilityScroll` so VoiceOver / Speak Screen advance automatically. For a lazy Flutter list, the equivalent "page" is the currently exposed semantic cache, including the few offscreen items Flutter prebuilds.

The iOS bridge experiment should therefore:

1. Find the owning `FlutterSemanticsScrollView` by the Flutter semantics parent chain rather than screen geometry.
2. Mark the last currently exposed focusable semantic descendant of that scrollable with `causesPageTurn`.
3. Translate `.next` page-turn requests to Flutter's vertical `.up` accessibility scroll (which dispatches `SemanticsAction.scrollDown`).
4. Handle the request whether UIKit sends it to the semantic item, its scroll container, the hidden semantics UIScrollView, or the Flutter view controller.
5. Post a `pageScrolled` accessibility notification after the semantic scroll, matching Apple's page-turn pattern.

Dart widget order/layout should remain unchanged while testing this native bridge.
