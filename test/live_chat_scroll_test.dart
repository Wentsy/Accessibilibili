import 'package:PiliPlus/common/a11y/voiceover_paged_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native live chat marker pages and dispatches edge actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var atStart = 0;
    var atEnd = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(accessibleNavigation: true),
      child: Scaffold(body: SizedBox(height: 200,
        child: VoiceOverPagedScroll(
          controller: scroll,
          nativeFeedScroll: true,
          onScrollBackwardAtStart: () => atStart++,
          onScrollForwardAtEnd: () => atEnd++,
          child: ListView(controller: scroll, children: const [
            SizedBox(height: 600, child: Text('彈幕')),
          ]),
        ),
      )),
    )));
    final marker = find.byWidgetPredicate((widget) => widget is Semantics &&
        widget.properties.identifier == 'a11y-feed-scroll|viewport');
    expect(marker, findsOneWidget);
    void action(SemanticsAction gesture) {
      final node = tester.getSemantics(marker);
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node.id, gesture);
    }
    action(SemanticsAction.scrollDown);
    await tester.pumpAndSettle();
    expect(atStart, 1);
    action(SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    action(SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    action(SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    action(SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    expect(atEnd, 1);
  });
}
