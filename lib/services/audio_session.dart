import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

class AudioSessionHandler with WidgetsBindingObserver {
  late AudioSession session;
  late final Future<void> _ready;
  bool _playInterrupted = false;

  bool get _keepIosBackgroundPlayback {
    if (!Platform.isIOS || !Pref.continuePlayInBackground) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return state != null && state != AppLifecycleState.resumed;
  }

  Future<bool> setActive(bool active) async {
    await _ready;

    if (Platform.isIOS) {
      // Normal pause/dispose paths intentionally keep the iOS session alive so
      // starting or stopping video never rebuilds the audio route underneath
      // VoiceOver. libmpv also skips AVAudioSession management on iOS, so the
      // app must reassert its own mixable session before every real playback.
      // Calling setActive(true) again without a matching deactivation is
      // idempotent, while avoiding a stale local "active" cache that can leave
      // background audio without an active system session after iOS lifecycle
      // transitions.
      if (!active) return true;
      return session.setActive(
        true,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      );
    }

    return session.setActive(
      active,
      avAudioSessionSetActiveOptions: active
          ? AVAudioSessionSetActiveOptions.none
          : AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  }

  AudioSessionHandler() {
    if (Platform.isIOS) {
      WidgetsBinding.instance.addObserver(this);
    }
    _ready = initSession();
    // The first playback request still observes initialization failures.
    _ready.ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) return;

    final controller = PlPlayerController.instance;
    if (controller == null) return;

    // The player controller snapshots this preference when it is created.
    // Always refresh that snapshot before PLVideoPlayer handles the same iOS
    // lifecycle event, otherwise a setting changed while the controller is
    // alive can still make its observer pause playback in the background.
    final continueInBackground = Pref.continuePlayInBackground;
    controller.continuePlayInBackground.value = continueInBackground;
    if (!continueInBackground) return;

    final player = controller.videoPlayerController;
    if (player == null) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // display-resample is tied to display vsync. iOS stops presenting
        // Flutter frames in the background, which can stall mpv's playback
        // clock and therefore its audio too. Use audio as the master clock
        // while the screen is unavailable, and keep the app-owned mixable
        // AVAudioSession asserted without ever deactivating it.
        setActive(true).ignore();
        player.setProperty('video-sync', 'audio');
        break;
      case AppLifecycleState.resumed:
        setActive(true).ignore();
        player.setProperty('video-sync', Pref.videoSync);
        break;
      case AppLifecycleState.detached:
        break;
    }
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

    // Warm the mixable iOS session before VoiceOver starts interacting with
    // playback UI. It is never deliberately deactivated during normal player
    // pause/dispose; setActive(true) before playback simply reasserts it.
    if (Platform.isIOS) {
      await session.setActive(
        true,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      );
    }

    session.interruptionEventStream.listen((event) {
      // audio_session maps an iOS interruption begin to `unknown`. When iOS is
      // moving this app into the background, treating that notification as a
      // media pause defeats the user's explicit background-play preference and
      // produces the system-like fade-out/fade-in heard on lock/home. Let the
      // system own the temporary interruption while keeping mpv logically
      // playing; when it ends, only reassert our mixable session.
      if (_keepIosBackgroundPlayback) {
        if (!event.begin) {
          setActive(true).ignore();
          if (_playInterrupted) {
            PlPlayerController.playIfExists();
            _playInterrupted = false;
          }
        }
        return;
      }

      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      if (event.begin) {
        if (playerStatus != PlayerStatus.playing) return;
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
            break;
          case AudioInterruptionType.pause:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            _playInterrupted = true;
            break;
          case AudioInterruptionType.unknown:
            PlPlayerController.pauseIfExists(isInterrupt: true);
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
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) PlPlayerController.playIfExists();
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
    });
  }
}
