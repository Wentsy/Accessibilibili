# Comment Read All diagnostics

The reported failure still reproduces after the reading-anchor change. This
commit adds bounded in-memory diagnostics; it does not claim to fix the stall.

On iOS, reproduce with VoiceOver two-finger swipe down. At the stalled comment,
use the Actions rotor to choose 複製朗讀診斷 and double-tap. Paste the report before
moving backward to recover. The action is available on main and nested comments.
The copy confirmation is spoken only after the snapshot has been captured.

The report includes actual bundle build/iOS version, counters and the last 240
events from each side. Timestamps are Unix milliseconds, allowing the native and
Dart timelines to be merged. It contains semantic IDs and geometry, not comment
text, user names, credentials, HTTP URLs or response/error bodies.

Interpretation:
- installTextLink reports whether the class-local runtime getter was installed.
- textLinkQuery/chainPosition/textLinkMissing establish whether Read All uses
  the custom chain and whether the current object is still in that chain.
- anchorSent/anchorReceived/anchorRun show whether the platform callback reaches
  a mounted Dart comment.
- focusGeometry/ensureVisible show viewport movement and suppression.
- readingScroll/boundaryDispatch/forward/advanceTarget/advanceComplete locate
  lost or coalesced page actions.
- loadStart/loadComplete/loadSkipped distinguish a loaded semantic boundary
  from a real loading failure/end state.
- notificationSent/pageScrolledReceived show the completion round trip.

No regression/defensive tests or IPA packaging were performed. Build numbers
remain owned by OpenCode.
