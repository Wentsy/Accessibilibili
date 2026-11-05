# Keep pagination status out of the active reading position

User feedback on the mounted-list implementation: more comments were read,
then VoiceOver spoke the loading status, apparently skipped far down the new
page, and stopped. The exact skipped range has not been measured.

Main comments supplied a sort key inside ReplyItemGrpc, but ReplyA11ySemantics
excludes that subtree and did not supply a sort key itself. The status had a
sort key. Main comment order is now set on the actual accessible row, and
vote/status/row widgets retain stable keys across appends.

On iOS VoiceOver, the transient loading text is visual only. Error and end
status remain accessible. This prevents the loading footer from becoming the
reading position before new comments are inserted ahead of it. It does not
restart speech, force focus, or assume network loading always completes before
the reader reaches the loaded end.

This is a targeted ordering correction; uninterrupted reading remains subject
to device validation.
