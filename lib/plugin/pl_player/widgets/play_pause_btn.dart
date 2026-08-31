import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final StreamSubscription<bool> subscription;
  late Player player;

  @override
  void initState() {
    super.initState();
    player = widget.plPlayerController.videoPlayerController!;
    controller = AnimationController(
      vsync: this,
      value: player.state.playing ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    subscription = player.stream.playing.listen((playing) {
      if (playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = player.state.playing;
    final label = isPlaying ? '暫停' : '播放';

    return Semantics(
      button: true,
      label: label,
      value: isPlaying ? '正在播放' : '已暫停',
      hint: '點兩下${isPlaying ? '暫停' : '播放'}影片',
      onTap: widget.plPlayerController.onDoubleTapCenter,
      excludeSemantics: true,
      child: SizedBox(
        width: 42,
        height: 34,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.plPlayerController.onDoubleTapCenter,
          child: Center(
            child: AnimatedIcon(
              progress: controller,
              icon: AnimatedIcons.play_pause,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
