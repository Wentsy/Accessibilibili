# Accepted page-turn intent must survive layout changes

The latest device trace reports 54 pageTurnTrait evaluations and readingScroll
direction=5 (.next), followed by direction=2. There is no boundaryDispatch and
no Dart forward event. Network loading succeeded (43 items, end=false).

The native .next handler re-ran shouldCauseForwardPageTurn before dispatch.
That predicate depends on the current last visible reply, which can change
between UIKit querying traits and delivering .next. The export shows focus on
anchor 6 while the last visible anchor is already 7. These observations locate
the missing dispatch and support a changing-boundary race.

For marked comment wrappers, route .next directly to the Dart forward action.
Dart determines whether it can scroll/load using current state and coalesces
in-flight turns. Keep the visible-boundary predicate for advertising traits,
and retain the old action policy for other reading groups.

No regression/defensive tests or packaging performed. The retained diagnostic
events can confirm boundaryDispatch -> forward -> advanceComplete on device.
