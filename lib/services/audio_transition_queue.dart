/// Serializes playback and audio-session handoffs, including across players.
/// A failed platform operation is reported to its caller without poisoning
/// subsequent pause, cleanup or playback requests.
class AudioTransitionQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }
}
