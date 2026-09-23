import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_emote/datum.dart';
import 'package:PiliPlus/models_new/live/live_emote/emoticon.dart';
import 'package:PiliPlus/pages/live_emote/controller.dart';
import 'package:PiliPlus/pages/live_emote/view.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class FakeEmotes extends LiveEmotePanelController {
  FakeEmotes() : super(42);
  @override
  void onInit() {} // No network request in this test.
}

void main() {
  for (final pkgType in [3, 1]) {
    testWidgets('focused live emote selects the same item, package $pkgType',
        (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      final controller = Get.put<LiveEmotePanelController>(FakeEmotes(), tag: '42');
      addTearDown(() => Get.reset());
      final emotes = List.generate(30, (i) => Emoticon(
        emoji: '[貼圖$i]', emoticonUnique: 'emote-$i',
      ));
      controller.customHandleResponse(true, Success([
        LiveEmoteDatum(pkgType: pkgType, emoticons: emotes),
      ]));
      Emoticon? selected;
      var inserted = 0;
      var sent = 0;
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Scaffold(body: SizedBox(height: 300, child: LiveEmotePanel(
          roomId: 42,
          onChoose: (emote, width, height) { selected = emote; inserted++; },
          onSendEmoticonUnique: (emote) { selected = emote; sent++; },
        ))),
      )));
      await tester.pumpAndSettle();
      final tile = find.byKey(ObjectKey(emotes[2]));
      final node = tester.getSemantics(tile);
      expect(node.label, '貼圖2 貼圖');
      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      owner.performAction(node.id, SemanticsAction.didGainAccessibilityFocus);
      await tester.pump();
      owner.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(identical(selected, emotes[2]), isTrue);
      expect(inserted, pkgType == 3 ? 1 : 0);
      expect(sent, pkgType == 3 ? 0 : 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
