import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/common/a11y/composer_dock.dart';
import '../lib/common/widgets/scaffold/simple_scaffold.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('composer stays below viewport at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      var activations = 0;

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            accessibleNavigation: true,
            padding: const EdgeInsets.only(bottom: 34),
            viewPadding: const EdgeInsets.only(bottom: 34),
          ),
          child: SimpleScaffold(
            body: CustomScrollView(
              controller: controller,
              slivers: [
                SliverFixedExtentList(
                  itemExtent: 100,
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => Text('reply $index'),
                    childCount: 40,
                  ),
                ),
              ],
            ),
            bottomBar: VoiceOverComposerDock(
              onPressed: () => activations++,
            ),
          ),
        ),
      ));

      final button = find.byWidgetPredicate((widget) => widget is FilledButton);
      final initialFrame = tester.getRect(button);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(viewport.bottom, lessThanOrEqualTo(initialFrame.top));
      expect(initialFrame.bottom, lessThanOrEqualTo(size.height - 34));
      expect(initialFrame.width, greaterThan(size.width * 0.8));

      controller.jumpTo(1400);
      await tester.pump();
      expect(tester.getRect(button), initialFrame);
      await tester.tap(button);
      expect(activations, 1);
      final node = tester.getSemantics(find.bySemanticsLabel('發表評論'));
      expect(node.getSemanticsData().identifier, 'a11y-touch-only|publish-comment');
      expect(tester.takeException(), isNull);
      // Flutter tests verify layout and the bridge marker. Native VoiceOver's
      // linear exclusion and touch hit-test still require an iPhone.
    });
  }

  testWidgets('dock is enabled only for iOS accessible navigation', (tester) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final accessible in [true, false]) {
        bool? enabled;
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(accessibleNavigation: accessible),
          child: Builder(builder: (context) {
            enabled = useVoiceOverComposerDock(context);
            return const SizedBox.shrink();
          }),
        ));
        expect(enabled, platform == TargetPlatform.iOS && accessible);
      }
    }
  });
}
