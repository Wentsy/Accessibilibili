import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool useVoiceOverComposerDock(BuildContext context) =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS &&
    MediaQuery.accessibleNavigationOf(context);

/// A real footer below the scroll viewport, using the existing iOS touch-only
/// semantic bridge. Never put this inside a scrollable or an overlaid FAB slot.
class VoiceOverComposerDock extends StatelessWidget {
  const VoiceOverComposerDock({
    super.key,
    required this.onPressed,
    this.reply = false,
  });

  final VoidCallback onPressed;
  final bool reply;

  @override
  Widget build(BuildContext context) {
    final label = reply ? '發表回覆' : '發表評論';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Semantics(
          container: true,
          excludeSemantics: true,
          identifier: reply
              ? 'a11y-touch-only|publish-reply'
              : 'a11y-touch-only|publish-comment',
          button: true,
          label: label,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 56,
              minWidth: double.infinity,
            ),
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.reply),
              label: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
