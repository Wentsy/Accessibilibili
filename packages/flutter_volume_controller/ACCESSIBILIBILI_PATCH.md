# App-owned iOS audio session

Vendored from `yosemiteyss/flutter_volume_controller` tag `v2.0.2`, commit
`def69b5f049aa9018b9c875200a1ffae7e99fe62` (the version previously in pubspec.lock).
The upstream LICENSE is included. Platform implementation files, Dart library,
package manifest and upstream documentation are retained; example apps and
upstream development/CI files are omitted.

Local changes:

- `VolumeListener.swift`: observe outputVolume without setting a category or
  activating/deactivating AVAudioSession. Cancelling only removes observation.
- `VolumeController.swift`: reading volume does not activate the session; remove
  the unused automatic activation/deactivation helpers.
- `FlutterVolumeControllerPlugin.swift`: remove foreground session activation
  and lifecycle registration; construct the passive listener.
- Dart addListener documentation records that its category argument is ignored
  by this app-specific iOS implementation. The public API remains compatible.

The explicit setIOSAudioSessionCategory API remains upstream-compatible, but
Accessibilibili must not call it: its category-only setter drops mixWithOthers.
Normal get/set volume, volume observation, and all non-iOS implementations are
otherwise retained. AudioSessionHandler remains the session owner.

When updating upstream, preserve these ownership boundaries. Do not merely pass
playback to addListener: that still calls setCategory without mixWithOthers and
can regress VoiceOver coexistence. See docs/IOS_BACKGROUND_AUDIO.md in the app.
