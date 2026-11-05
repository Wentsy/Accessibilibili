# Visible-page boundary follow-up

The second supplied device report records 28 comment focus events, 78 loaded
comments, end=false, and about 11,363 pixels of remaining Dart scroll extent.
There are no textLinkQuery, readingScroll or pageTurnTrait events. This rules
out an exhausted data page for this reproduction; it also shows that the
custom text-navigation getters still do not participate.

The existing causesPageTurn predicate selects the last reply in the entire
cached semantic subtree. Flutter retains several screens of replies, while
VoiceOver's visible page can end earlier. Select the last reply intersecting
the native viewport instead, within the marked comment wrapper. Continue
using Dart's forward-page marker to decide whether more viewport/data remains.

Export now reports cached node count and the last visible boundary identifier
for comparison with the focused identifier. The selection is a code-level
fix motivated by the trace, not a confirmed on-device resolution.

No regression/defensive tests or IPA packaging performed.
