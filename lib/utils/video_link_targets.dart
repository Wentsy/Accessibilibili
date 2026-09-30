import 'video_timestamps.dart';

class VideoLinkTarget {
  const VideoLinkTarget(this.label, this.destination, {this.time});
  final String label;
  final String destination;
  final Duration? time;
}

/// Keeps links in text order. A URL is consumed as a whole before parsing
/// timestamps, so port numbers and URL parameters cannot become seek targets.
List<VideoLinkTarget> parseVideoLinkTargets(
  String text, {
  int? durationMs,
  bool allowTimes = true,
  Map<String, String> titles = const {},
}) {
  final tokens = RegExp(
    [
      r'https?://[^\s<>]+',
      ...titles.keys.where((key) => key.isNotEmpty).map(RegExp.escape),
      r'(?<![a-zA-Z0-9])BV[a-zA-Z0-9]{10}(?![a-zA-Z0-9])',
      r'\d+(?:[:：]\d+)+',
    ].join('|'),
    caseSensitive: false,
  );
  final targets = <VideoLinkTarget>[];
  final seen = <String>{};
  for (final match in tokens.allMatches(text)) {
    var value = match[0]!;
    if (RegExp(r'^\d').hasMatch(value)) {
      if (!allowTimes) continue;
      final times = parseVideoTimestamps(value, durationMs: durationMs);
      if (times.isEmpty) continue;
      final time = times.single;
      if (!seen.add('time:${time.inSeconds}')) continue;
      targets.add(
        VideoLinkTarget('跳轉至 ${videoTimestampLabel(time)}', value, time: time),
      );
    } else {
      // Common trailing prose punctuation is not part of the destination.
      value = value.replaceFirst(RegExp(r'[，。；、！？,;!]+$'), '');
      if (!seen.add(value)) continue;
      final title = titles[value];
      targets.add(
        VideoLinkTarget(title?.isNotEmpty == true ? title! : value, value),
      );
    }
  }
  return targets;
}
