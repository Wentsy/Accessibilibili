import 'package:material_ui/material_ui.dart';

class ComBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final double width;
  final double height;
  final String? tooltip;

  const ComBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.width = 34,
    this.height = 34,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final child = Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: tooltip,
      hint: onTap != null ? '點兩下啟用' : null,
      excludeSemantics: tooltip != null,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: ExcludeSemantics(
          excluding: tooltip != null,
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onSecondaryTap,
            behavior: HitTestBehavior.opaque,
            child: icon,
          ),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: child);
    }
    return child;
  }
}
