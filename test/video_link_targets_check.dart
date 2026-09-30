// ignore_for_file: avoid_relative_lib_imports, avoid_print

// Run directly with `dart test/video_link_targets_check.dart` (no packages).
import '../lib/utils/video_link_targets.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final ordered = parseVideoLinkTargets(
    '開頭 00:05 BV1R2b56uEK7 https://example.com 1：02 結尾',
  );
  expect(ordered.length == 4, 'All timestamp, BV and URL targets are included');
  expect(
    ordered[0].time?.inSeconds == 5 &&
        ordered[1].destination == 'BV1R2b56uEK7' &&
        ordered[2].destination == 'https://example.com' &&
        ordered[3].time?.inSeconds == 62,
    'Targets preserve source order',
  );
  expect(
    parseVideoLinkTargets('01:02 1：02 00:03').length == 2,
    'Equivalent times are deduplicated',
  );
  expect(
    parseVideoLinkTargets('1:60 1:2:03 1:02:03:04').isEmpty,
    'Malformed times are rejected',
  );
  expect(
    parseVideoLinkTargets('00:05 02:01', durationMs: 120000).length == 1,
    'Known video duration bounds timestamp targets',
  );
  expect(
    parseVideoLinkTargets('00:05', durationMs: 0).single.time?.inSeconds == 5,
    'Unknown duration does not hide valid time targets',
  );
  final outside = parseVideoLinkTargets(
    '00:05 BV1R2b56uEK7',
    allowTimes: false,
  );
  expect(
    outside.length == 1 && outside.single.time == null,
    'No seek target outside a video',
  );
  final url = parseVideoLinkTargets('https://example.com:8080/watch?t=01:02，');
  expect(
    url.length == 1 &&
        url.single.time == null &&
        !url.single.destination.endsWith('，'),
    'Ports, URL timestamps and trailing prose punctuation are handled',
  );
  expect(
    parseVideoLinkTargets('BV1R2b56uEK7 BV1R2b56uEK7').length == 1,
    'Repeated BV targets are deduplicated',
  );
  final titled = parseVideoLinkTargets(
    'BV1R2b56uEK7',
    titles: {'BV1R2b56uEK7': '相關影片'},
  ).single;
  expect(
    titled.label == '相關影片' && titled.destination == 'BV1R2b56uEK7',
    'Friendly title preserves destination',
  );
  expect(
    parseVideoLinkTargets(
          'https://example.com/a/ BV1R2b56uEK7 https://example.com/b/',
        ).length ==
        3,
    'Distinct URLs remain separate',
  );
  print('11 video link target checks passed');
}
