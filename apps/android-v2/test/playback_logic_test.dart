import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/features/playback/playback_logic.dart';

void main() {
  test('language aliases match Jellyfin ISO 639-2 variants', () {
    const fra = MediaStreamInfo(
      index: 1,
      kind: StreamKind.audio,
      language: 'fra',
    );
    expect(matchesLanguage(fra, 'fre'), isTrue);
    expect(matchesLanguage(fra, 'eng'), isFalse);
    const none = MediaStreamInfo(index: 2, kind: StreamKind.audio);
    expect(matchesLanguage(none, 'eng'), isFalse);
  });

  test('preferred subtitle favours default text tracks', () {
    const item = CatalogItem(
      id: 'i',
      name: 'n',
      type: 'Movie',
      mediaStreams: [
        MediaStreamInfo(
          index: 3,
          kind: StreamKind.subtitle,
          language: 'eng',
          isTextSubtitle: false,
        ),
        MediaStreamInfo(
          index: 4,
          kind: StreamKind.subtitle,
          language: 'eng',
          isTextSubtitle: true,
        ),
      ],
    );
    expect(preferredSubtitleStream(item, 'eng')?.index, 4);
    expect(preferredSubtitleStream(item, null), isNull);
  });

  test('segments win; chapters fill in a missing intro and credits', () {
    final chapters = [
      const Chapter(name: 'Opening', startTicks: 0),
      const Chapter(name: 'Scene 1', startTicks: 60 * 10000000),
      const Chapter(name: 'End Credits', startTicks: 2400 * 10000000),
    ];
    final ranges = skipRanges(const [], chapters, durationSeconds: 2600);
    expect(ranges.map((r) => r.kind), [SkipKind.intro, SkipKind.outro]);
    expect(ranges.first.end, 60);
    expect(ranges.last.end, 2600);

    final withSegment = skipRanges(
      const [MediaSegment(SegmentKind.intro, 5 * 10000000, 40 * 10000000)],
      chapters,
      durationSeconds: 2600,
    );
    expect(withSegment.where((r) => r.kind == SkipKind.intro), hasLength(1));
    expect(withSegment.first.end, 40);
    expect(withSegment.first.contains(10), isTrue);
    expect(
      withSegment.first.contains(39.5),
      isFalse,
    ); // last second is not offered
  });

  test('transcode options override audio track and bitrate', () {
    final uri = withTranscodeOptions(
      Uri.parse(
        'http://jf/Videos/1/master.m3u8?MediaSourceId=s&AudioStreamIndex=1',
      ),
      audioIndex: 2,
      maxBitrate: 6000000,
    );
    expect(uri.queryParameters['AudioStreamIndex'], '2');
    expect(uri.queryParameters['MaxStreamingBitrate'], '6000000');
    expect(uri.queryParameters['MediaSourceId'], 's');
  });

  test('formatTime', () {
    expect(formatTime(const Duration(seconds: 75)), '01:15');
    expect(
      formatTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
