# Comment Read All: scroll completion status

## Device evidence

The supplied diagnostic records one accepted native `.next` request, one Dart
turn from 3286.30 to 3757.20, and one native `pageScrolledReceived`. There are
57 loaded comments, `end=false`, and more than 15000 points of remaining scroll
range. Export still reports the same focused comment (anchor 10); anchor 11
is the last visible comment. No subsequent Dart focus event appears.

This confirms that the scroll request and completion reached both sides of
the bridge. It does not prove why VoiceOver stopped reading.

## Change

The completion handler previously posted an empty string for every scroll.
Apple documents that repeated page-position descriptions indicate a boundary:
https://developer.apple.com/documentation/uikit/uiaccessibility/notification/pagescrolled

Comment paging now supplies a distinct, spoken completion description based on
successful forward turns in the current comment view. This counts viewport
turns, not API pages or total comments. Canceled/no-movement turns do not count.
The native handler forwards that description; other callers without a
description use nil instead of an empty string. Diagnostics record the supplied
description on both sides.

No focus-reset or announcement notification is added. Manual focus gestures,
pagination loading, and build numbers are unchanged.

## Validation

Source changes reviewed only. No build, regression tests, or device tests were
run, as requested. Continuous reading resumption remains unverified.
After an audible turn, check whether reading advances without another gesture.
If it stops, export before moving focus so the new position description and
subsequent focus events can be compared.
