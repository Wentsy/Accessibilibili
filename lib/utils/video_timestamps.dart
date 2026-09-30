/// Time links in comments/descriptions, in source order with duplicates removed.
List<Duration> parseVideoTimestamps(String text, {int? durationMs}) {
  final result = <Duration>[];
  final seen = <int>{};
  // Consume entire colon-separated tokens so malformed times cannot match a suffix.
  final pattern = RegExp(r'\d+(?:[:：]\d+)+');
  final urls = RegExp(
    r'https?://\S+',
    caseSensitive: false,
  ).allMatches(text).toList();
  for (final match in pattern.allMatches(text)) {
    if (urls.any((url) => match.start >= url.start && match.start < url.end)) {
      continue;
    }
    final parts = match[0]!.split(RegExp('[:：]'));
    if (parts.length < 2 ||
        parts.length > 3 ||
        parts.skip(1).any((part) => part.length != 2))
      continue;
    final values = parts.map(int.tryParse).toList();
    if (values.any((value) => value == null)) continue;
    if (values.last! >= 60 || (parts.length == 3 && values[1]! >= 60)) {
      continue;
    }
    final seconds = parts.length == 3
        ? values[0]! * 3600 + values[1]! * 60 + values[2]!
        : values[0]! * 60 + values[1]!;
    if (durationMs != null && durationMs > 0 && seconds * 1000 > durationMs) {
      continue;
    }
    if (seen.add(seconds)) result.add(Duration(seconds: seconds));
  }
  return result;
}

String videoTimestampLabel(Duration time) {
  final hours = time.inHours;
  final minutes = time.inMinutes.remainder(60);
  final seconds = time.inSeconds.remainder(60);
  return '${hours > 0 ? '$hours 小時 ' : ''}$minutes 分 $seconds 秒';
}
