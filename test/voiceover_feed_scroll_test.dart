import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/common/a11y/voiceover_paged_scroll.dart';

void main() {
  late ScrollController controller;
  late int refreshes;
  late int loads;

  setUp(() {
    controller = ScrollController();
    refreshes = 0;
    loads = 0;
  });
  tearDown(() => controller.dispose());

  Future<void> show(WidgetTester tester, {int count = 30, bool accessible = true}) async {
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(accessibleNavigation: accessible),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: VoiceOverPagedScroll(
              controller: controller,
              nativeFeedScroll: true,
              onScrollBackwardAtStart: () => refreshes++,
              onScrollForwardAtEnd: () => loads++,
              child: ListView.builder(
                controller: controller,
                itemExtent: 100,
                itemCount: count,
                itemBuilder: (_, index) => Text('Video $index'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder getWrapper() => find.byWidgetPredicate(
    (widget) => widget is Semantics &&
        widget.properties.identifier == 'a11y-feed-scroll|viewport',
  );

  Future<void> gesture(WidgetTester tester, SemanticsAction action) async {
    final node = tester.getSemantics(getWrapper());
    expect(node.getSemanticsData().hasAction(action), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, action);
    await tester.pumpAndSettle();
  }

  testWidgets('finger down maps to scrollUp: page backward, then refresh at top', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await show(tester);
    controller.jumpTo(200);
    await tester.pumpAndSettle();
    await gesture(tester, SemanticsAction.scrollUp);
    expect(controller.offset, 0);
    expect(refreshes, 0, reason: 'Reaching the edge is not a refresh');
    await gesture(tester, SemanticsAction.scrollUp);
    expect(refreshes, 1);
    expect(loads, 0);
  });

  testWidgets('finger up maps to scrollDown: page forward, then load at bottom', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await show(tester);
    await gesture(tester, SemanticsAction.scrollDown);
    expect(controller.offset, greaterThan(0));
    expect(loads, 0);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await gesture(tester, SemanticsAction.scrollDown);
    expect(loads, 1);
    expect(refreshes, 0);
  });

  for (final count in [0, 2]) {
    testWidgets('both boundary actions remain available with $count items', (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await show(tester, count: count);
      await gesture(tester, SemanticsAction.scrollUp);
      await gesture(tester, SemanticsAction.scrollDown);
      expect(refreshes, 1);
      expect(loads, 1);
    });
  }

  testWidgets('ordinary browsing does not install the native feed marker', (tester) async {
    await show(tester, accessible: false);
    expect(getWrapper(), findsNothing);
    expect(refreshes, 0);
    expect(loads, 0);
  });
}
