import 'package:PiliPlus/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart' show RenderBox, ChildLayoutHelper;
import 'package:material_ui/material_ui.dart';

enum BottomSheetType { bottomSheet, body }

class BottomSheetLayout
    extends SlottedMultiChildRenderObjectWidget<BottomSheetType, RenderBox> {
  const BottomSheetLayout({
    super.key,
    this.bottomSheet,
    this.excludeBodySemantics = false,
    required this.body,
  });

  final Widget? bottomSheet;
  final Widget body;
  /// Opt in for modal comment panels; keep the body mounted and laid out.
  final bool excludeBodySemantics;

  @override
  Iterable<BottomSheetType> get slots => BottomSheetType.values;

  @override
  Widget? childForSlot(slot) => switch (slot) {
    .bottomSheet => bottomSheet,
    .body => ExcludeSemantics(
      // 無障礙：底部面板（樓中樓、留言、圖片等）打開時，底下的頁面必須
      // 從語義樹移除。否則 VoiceOver 滑到面板最後一項後會「穿出去」，
      // 跑到後面那層的內容繼續唸。
      excluding: bottomSheet != null,
      child: body,
    ),
  };

  @override
  SlottedContainerRenderObjectMixin<BottomSheetType, RenderBox>
  createRenderObject(
    BuildContext context,
  ) {
    return _RenderScaffoldLayout();
  }
}

class _RenderScaffoldLayout extends RenderBox
    with
        SlottedContainerRenderObjectMixin<BottomSheetType, RenderBox>,
        SlottedLayoutMixin {
  RenderBox? get bottomSheet => childForSlot(.bottomSheet);
  RenderBox get body => childForSlot(.body)!;

  @override
  Iterable<BottomSheetType> get slots => BottomSheetType.values;

  @override
  void performLayout() {
    final constraints = this.constraints;
    size = constraints.biggest;

    final childConstraints = constraints.loosen();
    final body = this.body..layout(childConstraints);
    setOffset(body, .zero);

    final bottomSheet = this.bottomSheet;
    if (bottomSheet != null) {
      final size = ChildLayoutHelper.layoutChild(bottomSheet, childConstraints);
      setOffset(bottomSheet, Offset(0, constraints.maxHeight - size.height));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    void doPaint(RenderBox? child) {
      if (child != null) {
        context.paintChild(child, getOffset(child) + offset);
      }
    }

    doPaint(body);
    doPaint(bottomSheet);
  }
}
