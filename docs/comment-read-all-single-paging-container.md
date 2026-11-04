# One paging container for main comments

Device feedback after a3f5fb9: a nested thread with roughly 40–50 replies read
to the end, while main comments still stopped around 25. This establishes a
useful comparison, not proof of a universal fix for nested threads.

Main comments previously wrapped the comment paging node in an additional
a11y-feed-scroll container controlling the same ScrollController. The native
feed bridge redirects vertical accessibilityScroll requests to that ancestor.
Its forwardingReadAll exclusion covers app-dispatched reading requests, but
does not identify every system-originated vertical request during Read All.

Main comments now use the same single comment paging wrapper as nested replies.
The start-boundary refresh callback lives on that wrapper. Both paths retain
the real scroll metrics introduced in a3f5fb9. The inner Flutter list and its
native automatic scrolling remain present. There is no longer a feed-routing
ancestor added by ReplyPagedScroll.

This is a targeted removal of an extra routing layer. It still needs device
confirmation for continuous main-comment reading and explicit page gestures.
