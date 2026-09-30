import 'package:flutter_test/flutter_test.dart';
import 'package:PiliPlus/utils/video_timestamps.dart';

void main() {
  List<int> seconds(String text, {int? durationMs}) => parseVideoTimestamps(
    text,
    durationMs: durationMs,
  ).map((time) => time.inSeconds).toList();

  test('multiple timestamps, hours, full-width colons and source order', () {
    expect(seconds('開場0:00，重點12：34，結尾1:02:03，再看02:10'), [0, 754, 3723, 130]);
  });
  test('deduplicate equivalent times without reordering', () {
    expect(seconds('1:00 00:30 01：00 0:01:00'), [60, 30]);
  });
  test('reject malformed tokens and timestamps inside URLs', () {
    expect(
      seconds('1:60 1:99:00 1:02:03:04 1:2 https://a.test/12:34'),
      isEmpty,
    );
  });
  test('filter beyond duration, retain zero and exact end', () {
    expect(seconds('0:00 1:00 1:01', durationMs: 60000), [0, 60]);
    expect(seconds('0:00 1:01', durationMs: 0), [0, 61]);
  });
  test('spoken labels include hours without losing minutes', () {
    expect(videoTimestampLabel(const Duration(seconds: 3723)), '1 小時 2 分 3 秒');
  });
}
