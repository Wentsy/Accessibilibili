import 'dart:async';

/// Fetch the source while resolving the device's quality preferences. Neither
/// operation depends on the other's result. No CDN requests or speed tests.
Future<(T, bool?)> preparePlaybackSource<T>({
  required Future<T> Function() loadSource,
  required bool needsNetworkPreferences,
  required Future<bool> Function() readIsWiFi,
}) {
  return (
    loadSource(),
    needsNetworkPreferences ? readIsWiFi() : Future<bool?>.value(),
  ).wait;
}
