import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession session;
  late final Future<void> _ready;
  bool _playInterrupted = false;

  Future<bool> setActive(bool active) async {
    await _ready;
    return session.setActive(
      active,
      avAudioSessionSetActiveOptions: active
          ? AVAudioSessionSetActiveOptions.none
          : AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  }

  AudioSessionHandler() {
    _ready = initSession();
    // The first playback request still observes initialization failures.
    _ready.ignore();
  }

  Future<void> initSession() async {
    session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        // `playback` is non-mixable on iOS by default. Activating such a
        // session can cut off VoiceOver speech that is already in progress.
        // Keep the playback category, but explicitly allow simultaneous audio
        // so starting a video does not steal the accessibility speech channel.
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );

    session.interruptionEventStream.listen((event) {
      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      // final player = PlPlayerController.getInstance();
      if (event.begin) {
        if (playerStatus != PlayerStatus.playing) return;
        // if (!player.playerStatus.playing) return;
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Mobile volume control changes the iOS system output volume,
            // which also affects VoiceOver. Let iOS/VoiceOver handle its own
            // ducking instead of modifying the global volume here.
            if (!Platform.isIOS) {
              PlPlayerController.setVolumeIfExists(
                (PlPlayerController.getVolumeIfExists() ?? 0) * 0.5,
                showIndicator: false,
              );
            }
            // player.setVolume(player.volume.value * 0.5);
            break;
          case AudioInterruptionType.pause:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            break;
          case AudioInterruptionType.unknown:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (!Platform.isIOS) {
              PlPlayerController.setVolumeIfExists(
                (PlPlayerController.getVolumeIfExists() ?? 0) * 2,
                showIndicator: false,
              );
            }
            // player.setVolume(player.volume.value * 2);
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) PlPlayerController.playIfExists();
            //player.play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
        _playInterrupted = false;
      }
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      PlPlayerController.pauseIfExists();
      // final player = PlPlayerController.getInstance();
      // if (player.playerStatus.playing) {
      //   player.pause();
      // }
    });
  }
}
