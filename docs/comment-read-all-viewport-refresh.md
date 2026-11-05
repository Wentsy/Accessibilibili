# Refresh traversal after revealing a following reply

The latest device trace advances through 25 focus events and loads 77 comments.
There is no forced page turn. At export, anchor 24 remains focused while anchor
25 is visible, with a large remaining scroll range. This rules out a missing
network page for this stop, but does not establish the reason UIKit stopped.

The focus-driven jump now waits for the following Flutter frame's semantics
flush, then requests an iOS layoutChanged notification without a focus target.
The native handler queues the notification on the main queue and limits it to
a currently focused comment. This addresses the hypothesis that VoiceOver's
traversal snapshot has not picked up the newly exposed row. It does not force
focus, synthesize speech, or restart Read All.

Reference:
https://developer.apple.com/documentation/uikit/uiaccessibility/notification/layoutchanged

Diagnostics add replyViewportChangedSent and replyViewportChangedPosted.
Device confirmation is still needed, including whether the layout notification
itself affects ongoing speech. The existing geometry and focus traces remain.
