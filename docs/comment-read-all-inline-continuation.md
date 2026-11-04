# Continue through comments as list items

The latest device diagnostic confirms that the distinct page description reached
both Dart and iOS. A successful viewport scroll was followed by no new focus
event; export still identified the same comment. The user heard no new position
announcement. Therefore changing the completion description alone did not fix
Read All.

This change avoids the forced page-turn path when a successor comment is already
in the semantics tree. The current comment retains its text and identity as the
viewport moves; it is not a book page whose content changes after a turn.
Apple documents that causesPageTurn stops if the new content is unchanged:
https://developer.apple.com/documentation/uikit/uiaccessibilitytraits/causespageturn

On comment focus, Dart now reveals the row's trailing edge with 30% of viewport
height available below it. Unlike fractional item alignment, this reserves room
even when the comment is close to or taller than the viewport. It advances only
when needed and uses the nearest scroll position. Deferred focus recovery carries
the same option. Main comments and nested replies share these wrappers.

The native page-turn trait remains available at the end of the cached comment
chain; other reading groups retain their prior policy. Pagination prefetch,
explicit scrolling, and the completion description are retained.

New diagnostics: revealFollowingReply (actual target) and inlineContinuation
(cached successor instead of a forced page turn). Existing focus events show
whether traversal advances. No comment text is logged.

Source review only; no regression tests, build, or device validation performed.
The hypothesis and implementation still need real-device validation.
