import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/common/a11y/a11y_focus_scroll.dart';

void main() {
  late ScrollController controller;
  late Map<int, BuildContext> items;

  setUp(() {
    controller = ScrollController();
    items = {};
    suppressA11yFocusScroll(Duration.zero);
  });

  tearDown(() {
    controller.dispose();
    suppressA11yFocusScroll(Duration.zero);
  });

  Future<void> buildList(WidgetTester tester, {bool accessible = true}) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessible),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: ListView.builder(
                controller: controller,
                itemExtent: 100,
                cacheExtent: 400,
                itemCount: 30,
                itemBuilder: (context, index) => Builder(
                  builder: (context) {
                    items[index] = context;
                    return Text('Comment $index');
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('idle focus requests a frame and reveals following comments', (
    tester,
  ) async {
    await buildList(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    a11yEnsureVisible(items[3]!);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(controller.offset, greaterThan(0));
    final offset = controller.offset;
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.offset, offset, reason: 'No ongoing scroll animation');
  });

  testWidgets('already visible middle comment keeps the viewport still', (
    tester,
  ) async {
    await buildList(tester);
    a11yEnsureVisible(items[1]!, immediate: true);
    await tester.pump();
    expect(controller.offset, 0);
  });

  testWidgets('append suppression still blocks focus restoration scrolling', (
    tester,
  ) async {
    await buildList(tester);
    controller.jumpTo(800);
    await tester.pumpAndSettle();
    suppressA11yFocusScroll(const Duration(seconds: 5));
    a11yEnsureVisible(items[11]!, immediate: true);
    await tester.pump();
    expect(controller.offset, 800);
  });

  testWidgets('ordinary browsing does not trigger accessibility scrolling', (
    tester,
  ) async {
    await buildList(tester, accessible: false);
    a11yEnsureVisible(items[3]!);
    await tester.pump();
    expect(controller.offset, 0);
  });

  testWidgets('suppressed reply focus resumes without another swipe', (tester) async {
    await buildList(tester);
    suppressA11yFocusScroll(const Duration(milliseconds: 500));
    a11yEnsureVisible(items[3]!, recoverAfterSuppression: true);
    await tester.pump();
    expect(controller.offset, 0);
    // The suppression clock is wall time; explicitly expire it in fake time.
    suppressA11yFocusScroll(Duration.zero);
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('losing reply focus cancels deferred movement', (tester) async {
    await buildList(tester);
    suppressA11yFocusScroll(const Duration(milliseconds: 500));
    a11yEnsureVisible(items[3]!, recoverAfterSuppression: true);
    cancelDeferredReplyFocus(items[3]!);
    suppressA11yFocusScroll(Duration.zero);
    await tester.pump(const Duration(milliseconds: 501));
    expect(controller.offset, 0);
  });

  testWidgets('deferred restored node above viewport cannot jump backwards', (tester) async {
    await buildList(tester);
    controller.jumpTo(400);
    await tester.pumpAndSettle();
    suppressA11yFocusScroll(const Duration(milliseconds: 500));
    a11yEnsureVisible(items[1]!, recoverAfterSuppression: true);
    suppressA11yFocusScroll(Duration.zero);
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(controller.offset, 400);
  });
}
