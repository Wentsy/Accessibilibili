import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession session;
  late final Future<void> _ready;
  bool _playInterrupted = false;
  bool _iosSessionActive = false;

  Future<bool> setActive(bool active) async {
    await _ready;

    if (Platform.isIOS) {
      // Keep one mixable iOS audio session alive for the whole app lifetime.
      // Repeated activate/deactivate cycles can rebuild the system audio route
      // right as playback starts, which may clip VoiceOver mid-utterance even
      // though the category itself allows mixing.
      if (!active) return true;
      if (_iosSessionActive) return true;

      _iosSessionActive = await session.setActive(
        true,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      );
      return _iosSessionActive;
    }

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
        // so video audio and accessibility speech can coexist.
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

    // On iOS, activate the mixable session during app initialization instead
    // of at the instant a video begins. Normal pause/dispose paths intentionally
    // leave it active, avoiding route churn between VoiceOver and the player.
    if (Platform.isIOS) {
      _iosSessionActive = await session.setActive(
        true,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      );
    }

    session.interruptionEventStream.listen((event) {
      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      // final player = PlPlayerController.getInstance();
      if (event.begin) {
        // A real iOS interruption may deactivate the app's audio session. Mark
        // it for one legitimate reactivation after the interruption ends.
        if (Platform.isIOS && event.type != AudioInterruptionType.duck) {
          _iosSessionActive = false;
        }

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
