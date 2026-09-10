import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/common/widgets/progress_bar/audio_video_progress_bar.dart';

void main() {
  testWidgets('playback updates the existing adjustable semantics node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final seeks = <int>[];
    final OnSeek onSeek = seeks.add;

    Future<void> show(int progress, int total, {bool enabled = true}) {
      return tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            child: ProgressBar(
              progress: progress,
              total: total,
              onSeek: enabled ? onSeek : null,
              baseBarColor: Colors.grey,
              progressBarColor: Colors.blue,
              bufferedBarColor: Colors.white,
              thumbColor: Colors.blue,
              thumbGlowColor: Colors.blue,
            ),
          ),
        ),
      ));
    }

    final finder = find.bySemanticsLabel('影片播放進度');
    await show(10, 100);
    final nodeId = tester.getSemantics(finder).id;
    expect(tester.getSemantics(finder).value, '10 秒，共 1 分 40 秒，10%');

    // No touch/adjustment: only playback position changes, on the same node.
    await show(25, 100);
    var node = tester.getSemantics(finder);
    expect(node.id, nodeId);
    expect(node.value, '25 秒，共 1 分 40 秒，25%');
    expect(node.increasedValue, '35 秒，35%');
    expect(node.decreasedValue, '15 秒，15%');
    expect(seeks, isEmpty);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.increase,
    );
    await tester.pump();
    expect(seeks, [35000]);
    expect(tester.getSemantics(finder).value, '35 秒，共 1 分 40 秒，35%');

    await show(35, 200);
    node = tester.getSemantics(finder);
    expect(node.value, '35 秒，共 3 分 20 秒，18%');
    await show(35, 200, enabled: false);
    expect(
      tester.getSemantics(finder).getSemanticsData().hasAction(
        SemanticsAction.increase,
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
