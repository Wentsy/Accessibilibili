# Automatic playback route selection

Implementation candidate; not a new accessibility stable baseline until device testing.

- Enabled by default through `autoCdn`. Turning off “自动选择播放线路” restores the existing manual CDN choice for subsequent opens.
- Applies to regular video / PGC DASH, audio-only playback, and single-file MP4/FLV fallback. Live, local files, multi-segment legacy EDL, and manually edited media URLs keep their existing paths.
- Uses current API URLs plus a small set of mirrors through the existing CDN rewrite rules (at most six candidates). It never reuses expired signed URLs.
- Races at most two requests with playback User-Agent / Referer. Reads a 64 KiB sample, accepts only successful non-text media responses, and closes losing requests even when servers ignore Range. A shared 1.2 second deadline bounds each selection; failures may advance to the next candidate within that same deadline. Tiny samples are only a startup hint, not a guarantee of sustained throughput.
- Startup samples video (audio in audio-only mode); audio otherwise prefers the selected video host when available. If no probe succeeds in time, the original candidate remains available to the player. Audio and video can be tested separately on recovery.
- Fifteen seconds after opening, observed healthy playback can remember hosts for ten minutes in process memory. Connectivity changes invalidate that memory and cancel pending probes. There is no continuous speed testing during healthy playback.
- Eight seconds without position or buffer progress, together with buffering / network failure / failed opening, triggers silent recovery. At most three recovery attempts per source/network; already tried URLs are excluded. Preserve position, playback rate, subtitles, and pause intent. Seek, new source, disposal, and resumed progress prevent stale recovery from taking over.
- No toast, announcement, focus request, or new audio session for probing. Existing audio-session and buffering configuration remain in use. Switching media may still cause a short rebuffer; it is not guaranteed gapless.

Validation: standalone Dart HTTP-server regression test in
`test/services/auto_cdn_selector_test.dart` covers first successful sample,
concurrency limit, failed/HTML/tiny responses, ignored Range, deadline,
cancellation, fresh signed URLs, and network cache invalidation. Selector and
test pass Dart analysis. Full Flutter/iOS build and device playback testing
remain pending.
