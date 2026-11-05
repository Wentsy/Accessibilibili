# iOS VoiceOver comment list rewrite

User comparison with the earlier recommendation branch showed that nested
threads already tended to finish there. Their apparent success after the
metrics patch is not sufficient evidence of that patch resolving Read All.

For iOS accessible navigation, main comments and nested replies now keep every
loaded row mounted in a Column inside a SliverToBoxAdapter. The standard
CustomScrollView remains responsible for scrolling and native scroll semantics.
ReplyPagedScroll bypasses the custom paging container on this path. Comment
identifiers use a separate prefix so the old native reading hooks do not apply.

Focus only reveals an out-of-view item in its nearest scrollable. It does not
continually reposition visible rows. Existing last-five focus prefetch remains;
scroll progress within two viewports of the loaded end also requests more.
The eagerly built footer must not initiate a request, preventing build-driven
loading of all pages.

This targets lazy row removal / native traversal lifetime as a hypothesis.
It is not a confirmed root cause or a guarantee for iOS 18.7.8.
Memory and layout cost grow with loaded comments; no eviction is introduced
because retaining row identity is the purpose of this implementation.
Non-iOS and non-accessible list rendering retain their existing path.
