import 'dart:io' show Platform;

import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/services/audio_session.dart';

VideoPlayerServiceHandler? videoPlayerServiceHandler;
AudioSessionHandler? audioSessionHandler;

Future<void> setupServiceLocator() async {
  final audio = await initAudioService();
  videoPlayerServiceHandler = audio;

  final sessionHandler = AudioSessionHandler();
  audioSessionHandler = sessionHandler;

  if (Platform.isIOS) {
    try {
      // Finish the one-time mixable AVAudioSession activation before runApp.
      // This moves any route setup to app bootstrap rather than the instant a
      // VoiceOver user starts a video.
      await sessionHandler.setActive(true);
    } catch (_) {
      // Do not block app startup if iOS temporarily refuses activation. The
      // first real playback request can still retry through setActive(true).
    }
  }
}
