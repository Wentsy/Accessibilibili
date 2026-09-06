import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/common/widgets/scaffold/bottom_sheet_layout.dart';

Widget labeled(String label) => Semantics(
  container: true,
  label: label,
  child: const SizedBox(width: 200, height: 100),
);

Widget panel({required bool modal, Widget? sheet}) => Directionality(
  textDirection: TextDirection.ltr,
  child: BottomSheetLayout(
    excludeBodySemantics: modal,
    body: labeled('outer-comment'),
    bottomSheet: sheet,
  ),
);

void main() {
  testWidgets('ordinary sheets retain existing background semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(panel(modal: false, sheet: labeled('thread-comment')));
    expect(find.bySemanticsLabel('outer-comment'), findsOneWidget);
    expect(find.bySemanticsLabel('thread-comment'), findsOneWidget);
  });

  testWidgets('modal thread excludes background until the sheet is removed', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(panel(modal: false));
    final bodyElement = tester.element(find.bySemanticsLabel('outer-comment'));

    await tester.pumpWidget(panel(modal: true, sheet: labeled('thread-comment')));
    expect(find.bySemanticsLabel('outer-comment'), findsNothing);
    expect(find.bySemanticsLabel('thread-comment'), findsOneWidget);
    expect(bodyElement.mounted, isTrue);

    // The modal flag may remain set after dismissal; absence of a sheet must
    // restore the original body's semantics without remounting its state.
    await tester.pumpWidget(panel(modal: true));
    expect(find.bySemanticsLabel('outer-comment'), findsOneWidget);
    expect(tester.element(find.bySemanticsLabel('outer-comment')), same(bodyElement));
  });

  testWidgets('dialogue sheet excludes both outer and thread comments', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    Widget thread({Widget? dialogue}) => BottomSheetLayout(
      excludeBodySemantics: true,
      body: labeled('thread-comment'),
      bottomSheet: dialogue,
    );

    await tester.pumpWidget(panel(modal: true, sheet: thread(dialogue: labeled('dialogue-comment'))));
    expect(find.bySemanticsLabel('outer-comment'), findsNothing);
    expect(find.bySemanticsLabel('thread-comment'), findsNothing);
    expect(find.bySemanticsLabel('dialogue-comment'), findsOneWidget);

    await tester.pumpWidget(panel(modal: true, sheet: thread()));
    expect(find.bySemanticsLabel('outer-comment'), findsNothing);
    expect(find.bySemanticsLabel('thread-comment'), findsOneWidget);
  });
}
