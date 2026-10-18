import 'package:flutter_test/flutter_test.dart';
import 'package:soup_core/soup_core.dart';

const _tv = DeviceCapabilities(
  platform: 'webOS 10',
  videoCodecs: {'h264', 'hevc', 'av1', 'vp9'},
  audioDecoders: {'aac', 'mp3', 'flac', 'opus', 'ac3', 'eac3'},
  maxAudioChannels: 8,
  hevcMain10: true,
  hdr10: true,
  hlg: true,
  dolbyVision: true,
);

const _phone = DeviceCapabilities(
  platform: 'Android',
  videoCodecs: {'h264', 'hevc'},
  audioDecoders: {'aac', 'mp3', 'opus'},
  passthroughKnown: true,
  hevcMain10: true,
  maxVideoHeight: {'hevc': 2160},
);

Map<String, Object?> _directPlay(JellyfinDeviceProfile profile) =>
    (profile.toJson()['DirectPlayProfiles']! as List).single
        as Map<String, Object?>;

Map<String, Object?> _transcoding(JellyfinDeviceProfile profile) =>
    (profile.toJson()['TranscodingProfiles']! as List).single
        as Map<String, Object?>;

List<Map<String, Object?>> _codecProfiles(JellyfinDeviceProfile profile) => [
  for (final p in profile.toJson()['CodecProfiles']! as List)
    p as Map<String, Object?>,
];

String? _condition(Map<String, Object?> codecProfile, String property) {
  for (final c in codecProfile['Conditions']! as List) {
    final condition = c as Map<String, Object?>;
    if (condition['Property'] == property) return condition['Value'] as String;
  }
  return null;
}

void main() {
  test('direct plays MKV with every detected video codec', () {
    final profile = JellyfinDeviceProfile(capabilities: _tv);
    final direct = _directPlay(profile);
    expect((direct['Container']! as String).split(','), contains('mkv'));
    expect(direct['VideoCodec'], 'hevc,h264,av1,vp9');
  });

  test('copies HEVC into fMP4 HLS instead of re-encoding to H.264', () {
    final profile = JellyfinDeviceProfile(capabilities: _tv);
    final transcoding = _transcoding(profile);
    expect(transcoding['Container'], 'mp4');
    expect(transcoding['VideoCodec'], 'hevc,h264');
    final query = profile.transcodeQuery();
    expect(query['VideoCodec'], 'hevc,h264');
    expect(query['AllowVideoStreamCopy'], 'true');
    expect(query['hevc-videobitdepth'], '10');
  });

  test('advertises HDR10, HLG and Dolby Vision ranges the screen shows', () {
    final hevc = _codecProfiles(
      JellyfinDeviceProfile(capabilities: _tv),
    ).firstWhere((p) => p['Codec'] == 'hevc');
    final ranges = _condition(hevc, 'VideoRangeType')!.split('|');
    expect(
      ranges,
      containsAll([
        VideoRange.sdr,
        VideoRange.hdr10,
        VideoRange.hlg,
        VideoRange.dovi,
        VideoRange.doviWithHdr10,
        VideoRange.doviInvalid,
      ]),
    );
  });

  test('an SDR screen only gets SDR, so the server tone-maps HDR', () {
    final hevc = _codecProfiles(
      JellyfinDeviceProfile(capabilities: _phone),
    ).firstWhere((p) => p['Codec'] == 'hevc');
    expect(_condition(hevc, 'VideoRangeType'), 'SDR|DOVIWithSDR');
    expect(_condition(hevc, 'Height'), '2160');
  });

  test('Hi10P H.264 is never direct played', () {
    final h264 = _codecProfiles(
      JellyfinDeviceProfile(capabilities: _tv),
    ).firstWhere((p) => p['Codec'] == 'h264');
    expect(_condition(h264, 'VideoBitDepth'), '8');
  });

  test('10-bit VP9 and AV1 only direct play where detected', () {
    const plain = DeviceCapabilities(
      platform: 'Android',
      videoCodecs: {'h264', 'vp9', 'av1'},
      audioDecoders: {'aac'},
    );
    const tenBit = DeviceCapabilities(
      platform: 'Android',
      videoCodecs: {'h264', 'vp9', 'av1'},
      audioDecoders: {'aac'},
      vp9Profile2: true,
      av1Main10: true,
    );
    for (final codec in const ['vp9', 'av1']) {
      Map<String, Object?> of(DeviceCapabilities caps) => _codecProfiles(
        JellyfinDeviceProfile(capabilities: caps),
      ).firstWhere((p) => p['Codec'] == codec);
      expect(_condition(of(plain), 'VideoBitDepth'), '8', reason: codec);
      expect(_condition(of(tenBit), 'VideoBitDepth'), isNull, reason: codec);
    }
  });

  test('8-bit-only HEVC decoders are limited to Main', () {
    const caps = DeviceCapabilities(
      platform: 'Android',
      videoCodecs: {'h264', 'hevc'},
      audioDecoders: {'aac'},
    );
    final hevc = _codecProfiles(
      JellyfinDeviceProfile(capabilities: caps),
    ).firstWhere((p) => p['Codec'] == 'hevc');
    expect(_condition(hevc, 'VideoBitDepth'), '8');
    expect(_condition(hevc, 'VideoProfile'), 'main');
  });

  group('audio output', () {
    test('Auto plays Dolby on a TV and converts the rest to 5.1 AC3', () {
      final profile = JellyfinDeviceProfile(capabilities: _tv);
      expect(profile.directAudioCodecs, containsAll(['ac3', 'eac3']));
      expect(profile.directAudioCodecs, isNot(contains('truehd')));
      expect(profile.directAudioCodecs, isNot(contains('dts')));
      final transcoding = _transcoding(profile);
      expect(transcoding['AudioCodec'], 'ac3,aac');
      expect(transcoding['MaxAudioChannels'], '6');
    });

    test('Auto on a stereo phone converts to stereo AAC', () {
      final profile = JellyfinDeviceProfile(capabilities: _phone);
      final transcoding = _transcoding(profile);
      expect(transcoding['AudioCodec'], 'aac');
      expect(transcoding['MaxAudioChannels'], '2');
    });

    test('Auto passes through what the HDMI sink reports', () {
      const box = DeviceCapabilities(
        platform: 'Android',
        videoCodecs: {'h264', 'hevc'},
        audioDecoders: {'aac'},
        audioPassthrough: {'ac3', 'eac3', 'truehd', 'dts'},
        passthroughKnown: true,
        maxAudioChannels: 8,
      );
      final profile = JellyfinDeviceProfile(capabilities: box);
      expect(profile.directAudioCodecs, containsAll(['truehd', 'dts']));
    });

    test('Surround only trusts AC3 with more than two channels', () {
      final profile = JellyfinDeviceProfile(
        capabilities: _tv,
        audioOutput: AudioOutputMode.surround,
      );
      expect(profile.directAudioCodecs, contains('ac3'));
      expect(profile.directAudioCodecs, isNot(contains('eac3')));
      final limits = {
        for (final p in _codecProfiles(profile))
          if (p['Type'] == 'VideoAudio')
            p['Codec']: _condition(p, 'AudioChannels'),
      };
      expect(limits['ac3'], '6');
      expect(limits['aac'], '2');
      expect(_transcoding(profile)['MaxAudioChannels'], '6');
    });

    test('Stereo downmixes everything on the server', () {
      final profile = JellyfinDeviceProfile(
        capabilities: _tv,
        audioOutput: AudioOutputMode.stereo,
      );
      final limits = [
        for (final p in _codecProfiles(profile))
          if (p['Type'] == 'VideoAudio') _condition(p, 'AudioChannels'),
      ];
      expect(limits, isNotEmpty);
      expect(limits.toSet(), {'2'});
      expect(_transcoding(profile)['AudioCodec'], 'aac');
      expect(_transcoding(profile)['MaxAudioChannels'], '2');
    });

    test('Passthrough sends lossless formats when the sink is unknown', () {
      final profile = JellyfinDeviceProfile(
        capabilities: _tv,
        audioOutput: AudioOutputMode.passthrough,
      );
      expect(
        profile.directAudioCodecs,
        containsAll(['ac3', 'eac3', 'truehd', 'dts']),
      );
    });

    test('parses saved modes and falls back to Auto', () {
      expect(AudioOutputMode.parse('surround'), AudioOutputMode.surround);
      expect(AudioOutputMode.parse('nonsense'), AudioOutputMode.auto);
      expect(AudioOutputMode.parse(null), AudioOutputMode.auto);
    });
  });

  test('profile name and bitrate are carried into the JSON', () {
    final json = JellyfinDeviceProfile(
      capabilities: _tv,
      name: 'Living room TV',
      maxStreamingBitrate: 50000000,
    ).toJson();
    expect(json['Name'], 'Living room TV');
    expect(json['MaxStreamingBitrate'], 50000000);
  });

  test('device names are made safe for the Authorization header', () {
    expect(JellyfinApi.headerSafeDeviceName('Jeff\'s "TV", 4K'), 'Jeffs TV 4K');
    expect(JellyfinApi.headerSafeDeviceName('  '), 'Soup');
    expect(JellyfinApi.headerSafeDeviceName('LG OLED65C5'), 'LG OLED65C5');
  });

  group('language preferences', () {
    test('reads codes and treats SubtitleMode None as off', () {
      final prefs = JellyfinLanguagePreferences.fromConfiguration({
        'AudioLanguagePreference': 'JPN',
        'SubtitleLanguagePreference': 'eng',
        'SubtitleMode': 'None',
      });
      expect(prefs.audioLanguage, 'jpn');
      expect(prefs.subtitleLanguage, isNull);
    });

    test('writes only its own keys and keeps the rest', () {
      const prefs = JellyfinLanguagePreferences(
        audioLanguage: 'jpn',
        subtitleLanguage: 'eng',
      );
      final config = prefs.applyTo({
        'HidePlayedInLatest': true,
        'SubtitleMode': 'Default',
      });
      expect(config['HidePlayedInLatest'], true);
      expect(config['AudioLanguagePreference'], 'jpn');
      expect(config['PlayDefaultAudioTrack'], false);
      expect(config['SubtitleLanguagePreference'], 'eng');
      expect(config['SubtitleMode'], 'Always');
      expect(
        const JellyfinLanguagePreferences().applyTo({})['SubtitleMode'],
        'None',
      );
    });
  });
}
