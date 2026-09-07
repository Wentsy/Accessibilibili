import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

class AudioSessionHandler with WidgetsBindingObserver {
  static const MethodChannel _backgroundAudioChannel = MethodChannel(
    'accessibilibili/background_audio',
  );

  late AudioSession session;
  late final Future<void> _ready;
  bool _playInterrupted = false;
  int _iosSessionModeRequest = 0;

  AudioSessionConfiguration _iosPlaybackConfiguration({
    required bool mixWithVoiceOver,
  }) {
    return AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: mixWithVoiceOver
          ? AVAudioSessionCategoryOptions.mixWithOthers
          : AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    );
  }

  Future<void> _syncIosBackgroundPlaybackPreference() async {
    if (!Platform.isIOS) return;
    try {
      await _backgroundAudioChannel.invokeMethod<void>(
        'setBackgroundPlaybackEnabled',
        Pref.continuePlayInBackground,
      );
    } catch (_) {
      // Keep the existing audio_session lifecycle path as a fallback if the
      // local native wrapper is temporarily unavailable during app bootstrap.
    }
  }

  Future<void> _setIosPlaybackRole({required bool foreground}) async {
    final request = ++_iosSessionModeRequest;
    await _ready;
    if (request != _iosSessionModeRequest) return;

    // A mixing session lets video audio coexist with VoiceOver, but iOS treats
    // it as secondary audio and does not route the system Magic Tap to its
    // MPRemoteCommandCenter. Become the primary Now Playing session only while
    // actually backgrounded. Restore mixing before foreground interaction.
    await session.configure(
      _iosPlaybackConfiguration(mixWithVoiceOver: foreground),
    );
    if (request != _iosSessionModeRequest) return;
    await session.setActive(
      true,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
    );
  }

  bool get _keepIosBackgroundPlayback {
    if (!Platform.isIOS || !Pref.continuePlayInBackground) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return state != null && state != AppLifecycleState.resumed;
  }

  Future<bool> setActive(bool active) async {
    await _ready;

    if (Platform.isIOS) {
      // Persist the latest background-play preference in native code while the
      // app is still safely executing in the foreground. This is especially
      // important for the "pause first, then leave the app" path: once mpv has
      // stopped its AudioUnit, Flutter may be suspended before an async session
      // reconfiguration can finish.
      _syncIosBackgroundPlaybackPreference().ignore();

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
    _syncIosBackgroundPlaybackPreference().ignore();
    if (!continueInBackground) return;

    final player = controller.videoPlayerController;
    if (player == null) return;

    switch (state) {
      case AppLifecycleState.inactive:
        // `inactive` also covers temporary overlays and transitions. Keep the
        // proven foreground mixWithOthers role here so VoiceOver remains
        // uninterrupted. The local iOS wrapper performs the non-mixable switch
        // synchronously at UIScene.didEnterBackground, after this point.
        setActive(true).ignore();
        player.setProperty('video-sync', 'audio');
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // display-resample is tied to display vsync. iOS stops presenting
        // Flutter frames in the background, which can stall mpv's playback
        // clock and therefore its audio too. Use audio as the master clock.
        // Native scene lifecycle has already synchronously promoted the
        // AVAudioSession; reassert it here as a redundant async fallback.
        _setIosPlaybackRole(foreground: false).ignore();
        player.setProperty('video-sync', 'audio');
        break;
      case AppLifecycleState.resumed:
        _setIosPlaybackRole(foreground: true).ignore();
        player.setProperty('video-sync', Pref.videoSync);
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> initSession() async {
    session = await AudioSession.instance;
    await session.configure(
      _iosPlaybackConfiguration(mixWithVoiceOver: true),
    );

    // Warm the mixable iOS session before VoiceOver starts interacting with
    // playback UI. It is never deliberately deactivated during normal player
    // pause/dispose; setActive(true) before playback simply reasserts it.
    if (Platform.isIOS) {
      await session.setActive(
        true,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      );
      await _syncIosBackgroundPlaybackPreference();
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
