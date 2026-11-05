# Device trace findings

The supplied iOS 18.7.8 trace has 59 Dart focus events, but no native
textLinkQuery, anchorSent or readingScroll events. The installed text-navigation
getters are not exercised in this reproduction, so previous getter-based
recovery cannot explain or resolve this device's stall.

At export, Dart pixels=9983.3705 and max=10255.7865 (272.416 pixels remain).
The native ancestor reports offset=0, contentHeight=554, viewportHeight=554.
Three requests succeeded; the last reports count=41 and end=true. This does not
establish whether the server end flag is incorrect, but it does establish that
server pagination end and viewport end are different states.

Changes:
- Prefer a Flutter native ancestor with actual vertical range over a zero-range
  or horizontal container, retaining the first candidate only as fallback.
- Keep the reply wrapper's forward-page marker active while Dart has remaining
  scroll extent, even when server pagination ended; update it on scroll changes.
- Limit comment focus-driven ensureVisible to its owning scroll position.

No regression/defensive tests or package build were run. Device validation is
still required; retained diagnostics can verify the selected native viewport
and whether forward/page-turn events now occur.
