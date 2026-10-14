/// What a playback device can decode, display and send to its audio output,
/// and the Jellyfin `DeviceProfile` built from it.
///
/// Capabilities are detected per device (Android asks MediaCodec, the display
/// and the HDMI sink; webOS reads the TV's model info). The user's
/// [AudioOutputMode] then decides which audio Jellyfin may send untouched and
/// what it converts the rest to.
library;

/// How audio should reach this device's speakers, receiver or soundbar.
enum AudioOutputMode {
  /// Use what the device reports: formats it can decode or pass through play
  /// as-is, everything else becomes 5.1 Dolby Digital (or stereo AAC when the
  /// output is stereo).
  auto,

  /// Downmix everything to two channels on the server.
  stereo,

  /// The output takes Dolby Digital 5.1: AC3 plays as-is, other multichannel
  /// audio becomes 5.1 AC3, stereo tracks play as-is.
  surround,

  /// A receiver handles lossless and object audio: pass TrueHD, DTS and
  /// friends through untouched.
  passthrough;

  static AudioOutputMode parse(String? value) => AudioOutputMode.values
      .firstWhere((mode) => mode.name == value, orElse: () => auto);
}

/// Jellyfin `VideoRangeType` values.
abstract final class VideoRange {
  static const sdr = 'SDR';
  static const hdr10 = 'HDR10';
  static const hlg = 'HLG';
  static const hdr10Plus = 'HDR10Plus';

  /// Dolby Vision without a fallback layer (profile 5).
  static const dovi = 'DOVI';
  static const doviWithHdr10 = 'DOVIWithHDR10';
  static const doviWithHlg = 'DOVIWithHLG';
  static const doviWithSdr = 'DOVIWithSDR';
  static const doviWithEl = 'DOVIWithEL';
  static const doviWithHdr10Plus = 'DOVIWithHDR10Plus';
  static const doviWithElHdr10Plus = 'DOVIWithELHDR10Plus';

  /// Dolby Vision metadata Jellyfin doesn't recognise, e.g. profile 8 with
  /// compatibility ID 6 on many UHD Blu-ray encodes. The base layer is HDR10.
  static const doviInvalid = 'DOVIInvalid';
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.platform,
    required this.videoCodecs,
    required this.audioDecoders,
    this.audioPassthrough = const {},
    this.passthroughKnown = false,
    this.maxAudioChannels = 2,
    this.hevcMain10 = false,
    this.hdr10 = false,
    this.hlg = false,
    this.hdr10Plus = false,
    this.dolbyVision = false,
    this.maxVideoHeight = const {},
  });

  /// Shown in Settings, e.g. `Android` or `webOS 10`.
  final String platform;

  /// Jellyfin codec names: `h264`, `hevc`, `av1`, `vp9`, `vp8`.
  final Set<String> videoCodecs;

  /// Audio the device decodes itself (Jellyfin codec names).
  final Set<String> audioDecoders;

  /// Audio the output (HDMI sink) accepts as a bitstream.
  final Set<String> audioPassthrough;

  /// Whether [audioPassthrough] was reported by the device rather than
  /// unknown. webOS can't see past the TV, so Passthrough mode then assumes
  /// the receiver takes everything.
  final bool passthroughKnown;

  /// Channels the output can play; 2 on phones and headphones.
  final int maxAudioChannels;

  final bool hevcMain10;
  final bool hdr10;
  final bool hlg;
  final bool hdr10Plus;
  final bool dolbyVision;

  /// Largest frame height per video codec the device decodes smoothly;
  /// missing means no limit.
  final Map<String, int> maxVideoHeight;

  /// What any Android device can play: the codecs Android requires plus 8-bit
  /// HEVC, stereo out. Used until detection finishes and in tests.
  static const fallback = DeviceCapabilities(
    platform: 'Android',
    videoCodecs: {'h264', 'hevc', 'vp9'},
    audioDecoders: {'aac', 'mp3', 'opus', 'flac', 'vorbis'},
    maxVideoHeight: {'hevc': 1080, 'vp9': 1080},
  );

  /// Dynamic ranges the screen shows, with the Dolby Vision and HDR10+
  /// variants whose base layer it can fall back to (players ignore the extra
  /// metadata).
  List<String> get videoRanges => [
    VideoRange.sdr,
    VideoRange.doviWithSdr,
    if (hdr10) ...[
      VideoRange.hdr10,
      VideoRange.hdr10Plus,
      VideoRange.doviWithHdr10,
      VideoRange.doviWithEl,
      VideoRange.doviWithHdr10Plus,
      VideoRange.doviWithElHdr10Plus,
      VideoRange.doviInvalid,
    ],
    if (hlg) ...[VideoRange.hlg, VideoRange.doviWithHlg],
    if (dolbyVision) VideoRange.dovi,
  ];

  /// Short summary for Settings, e.g. `HEVC 10-bit · AV1 · HDR10 · Dolby Vision`.
  String get summary {
    final parts = <String>[
      if (videoCodecs.contains('hevc')) hevcMain10 ? 'HEVC 10-bit' : 'HEVC',
      if (videoCodecs.contains('av1')) 'AV1',
      if (videoCodecs.contains('vp9')) 'VP9',
      if (hdr10) 'HDR10',
      if (hdr10Plus) 'HDR10+',
      if (hlg) 'HLG',
      if (dolbyVision) 'Dolby Vision',
    ];
    return parts.join(' · ');
  }

  /// Audio formats sent to the output as a bitstream, for Settings.
  String get passthroughSummary {
    if (!passthroughKnown) return 'Not reported by this device';
    if (audioPassthrough.isEmpty) return 'None';
    return [
      for (final codec in _passthroughOrder)
        if (audioPassthrough.contains(codec)) _audioLabels[codec]!,
    ].join(', ');
  }

  Map<String, Object?> toJson() => {
    'platform': platform,
    'videoCodecs': videoCodecs.toList(),
    'audioDecoders': audioDecoders.toList(),
    'audioPassthrough': audioPassthrough.toList(),
    'passthroughKnown': passthroughKnown,
    'maxAudioChannels': maxAudioChannels,
    'hevcMain10': hevcMain10,
    'hdr10': hdr10,
    'hlg': hlg,
    'hdr10Plus': hdr10Plus,
    'dolbyVision': dolbyVision,
    'maxVideoHeight': maxVideoHeight,
  };

  static const _passthroughOrder = ['ac3', 'eac3', 'truehd', 'dts'];
  static const _audioLabels = {
    'ac3': 'Dolby Digital',
    'eac3': 'Dolby Digital Plus',
    'truehd': 'Dolby TrueHD',
    'dts': 'DTS',
  };
}

/// A Jellyfin `DeviceProfile` for one device and audio setting, plus the
/// query a hand-built HLS request needs to match it.
class JellyfinDeviceProfile {
  JellyfinDeviceProfile({
    required this.capabilities,
    this.audioOutput = AudioOutputMode.auto,
    this.name = 'Soup',
    this.maxStreamingBitrate = defaultMaxStreamingBitrate,
  });

  /// High enough for 4K Blu-ray encodes on a home network. A quality cap the
  /// user picks still applies on top.
  static const defaultMaxStreamingBitrate = 120000000;

  final DeviceCapabilities capabilities;
  final AudioOutputMode audioOutput;
  final String name;
  final int maxStreamingBitrate;

  static const _videoContainers = 'mkv,mp4,m4v,mov,ts,webm';

  /// Audio played as-is (subject to [_audioChannelLimits]).
  Set<String> get directAudioCodecs {
    final caps = capabilities;
    final decoders = caps.audioDecoders;
    switch (audioOutput) {
      case AudioOutputMode.stereo:
        return decoders;
      case AudioOutputMode.surround:
        return {...decoders.difference(_surroundOnly), 'ac3'};
      case AudioOutputMode.passthrough:
        final passthrough =
            caps.passthroughKnown && caps.audioPassthrough.isNotEmpty
            ? caps.audioPassthrough
            : const {'ac3', 'eac3', 'truehd', 'dts'};
        return {...decoders, ...passthrough};
      case AudioOutputMode.auto:
        return {...decoders, ...caps.audioPassthrough};
    }
  }

  /// Dolby formats that Surround mode converts to AC3 rather than trusting the
  /// output with.
  static const _surroundOnly = {'eac3', 'truehd', 'dts'};

  /// Codec Jellyfin converts audio to, best first.
  List<String> get transcodeAudioCodecs {
    if (_transcodeChannels <= 2) return const ['aac'];
    return const ['ac3', 'aac'];
  }

  int get _transcodeChannels {
    final caps = capabilities;
    switch (audioOutput) {
      case AudioOutputMode.stereo:
        return 2;
      case AudioOutputMode.surround:
      case AudioOutputMode.passthrough:
        return 6;
      case AudioOutputMode.auto:
        final canSendAc3 =
            caps.audioPassthrough.contains('ac3') ||
            caps.audioDecoders.contains('ac3');
        return canSendAc3 && caps.maxAudioChannels >= 6 ? 6 : 2;
    }
  }

  /// Per-codec channel limits for audio that plays as-is.
  Map<String, int> get _audioChannelLimits {
    switch (audioOutput) {
      case AudioOutputMode.stereo:
        return {for (final codec in directAudioCodecs) codec: 2};
      case AudioOutputMode.surround:
        // Only Dolby Digital reaches the output as multichannel.
        return {
          for (final codec in directAudioCodecs) codec: codec == 'ac3' ? 6 : 2,
        };
      case AudioOutputMode.auto:
      case AudioOutputMode.passthrough:
        return const {};
    }
  }

  List<String> get _videoCodecs => [
    for (final codec in const ['hevc', 'h264', 'av1', 'vp9', 'vp8'])
      if (capabilities.videoCodecs.contains(codec)) codec,
  ];

  /// Codecs the server may copy into HLS instead of re-encoding.
  List<String> get _transcodeVideoCodecs => [
    if (capabilities.videoCodecs.contains('hevc')) 'hevc',
    'h264',
  ];

  Map<String, Object?> toJson() {
    final audio = directAudioCodecs.toList()..sort();
    return {
      'Name': name,
      'MaxStreamingBitrate': maxStreamingBitrate,
      'MaxStaticBitrate': maxStreamingBitrate,
      'MusicStreamingTranscodingBitrate': 384000,
      'DirectPlayProfiles': [
        {
          'Container': _videoContainers,
          'Type': 'Video',
          'VideoCodec': _videoCodecs.join(','),
          'AudioCodec': audio.join(','),
        },
      ],
      'TranscodingProfiles': [
        {
          // fMP4 HLS carries HEVC, HDR10 and Dolby Vision when the video is
          // copied rather than re-encoded.
          'Container': 'mp4',
          'Type': 'Video',
          'VideoCodec': _transcodeVideoCodecs.join(','),
          'AudioCodec': transcodeAudioCodecs.join(','),
          'Protocol': 'hls',
          'Context': 'Streaming',
          'EnableSubtitlesInManifest': false,
          'MaxAudioChannels': '$_transcodeChannels',
          'MinSegments': 1,
          'SegmentLength': 6,
          'BreakOnNonKeyFrames': true,
        },
      ],
      'CodecProfiles': [..._videoCodecProfiles(), ..._audioCodecProfiles()],
      'SubtitleProfiles': [
        for (final format in const ['vtt', 'srt', 'ass', 'ssa'])
          {'Format': format, 'Method': 'External'},
      ],
    };
  }

  List<Map<String, Object?>> _videoCodecProfiles() {
    final caps = capabilities;
    final ranges = caps.videoRanges.join('|');
    return [
      {
        // Hardware H.264 decoders only handle 8-bit High/Main/Baseline; Hi10P
        // (common in older anime encodes) has to be converted.
        'Type': 'Video',
        'Codec': 'h264',
        'Conditions': [
          _condition('LessThanEqual', 'VideoBitDepth', '8'),
          _condition(
            'EqualsAny',
            'VideoProfile',
            'high|main|baseline|constrained baseline',
          ),
          _condition('EqualsAny', 'VideoRangeType', VideoRange.sdr),
          ..._heightCondition('h264'),
        ],
      },
      for (final codec in const ['hevc', 'av1', 'vp9'])
        if (caps.videoCodecs.contains(codec))
          {
            'Type': 'Video',
            'Codec': codec,
            'Conditions': [
              if (codec == 'hevc' && !caps.hevcMain10) ...[
                _condition('LessThanEqual', 'VideoBitDepth', '8'),
                _condition('EqualsAny', 'VideoProfile', 'main'),
              ],
              _condition('EqualsAny', 'VideoRangeType', ranges),
              ..._heightCondition(codec),
            ],
          },
    ];
  }

  List<Map<String, Object?>> _heightCondition(String codec) {
    final limit = capabilities.maxVideoHeight[codec];
    if (limit == null) return const [];
    return [_condition('LessThanEqual', 'Height', '$limit')];
  }

  List<Map<String, Object?>> _audioCodecProfiles() => [
    for (final MapEntry(key: codec, value: channels)
        in _audioChannelLimits.entries)
      {
        'Type': 'VideoAudio',
        'Codec': codec,
        'Conditions': [
          _condition('LessThanEqual', 'AudioChannels', '$channels'),
        ],
      },
  ];

  static Map<String, Object?> _condition(
    String condition,
    String property,
    String value,
  ) => {
    'Condition': condition,
    'Property': property,
    'Value': value,
    'IsRequired': false,
  };

  /// Query for `Videos/{id}/master.m3u8` when Jellyfin offered no
  /// `TranscodingUrl`: copy the video when the device plays it, convert only
  /// what it can't.
  Map<String, String> transcodeQuery() {
    final caps = capabilities;
    final ranges = caps.videoRanges.join(',');
    return {
      'VideoCodec': _transcodeVideoCodecs.join(','),
      'AudioCodec': transcodeAudioCodecs.join(','),
      'TranscodingMaxAudioChannels': '$_transcodeChannels',
      'SegmentContainer': 'mp4',
      'MinSegments': '1',
      'BreakOnNonKeyFrames': 'true',
      'AllowVideoStreamCopy': 'true',
      'AllowAudioStreamCopy': 'true',
      'RequireAvc': 'false',
      'h264-videobitdepth': '8',
      'h264-rangetype': VideoRange.sdr,
      if (caps.videoCodecs.contains('hevc')) ...{
        'hevc-videobitdepth': caps.hevcMain10 ? '10' : '8',
        'hevc-rangetype': ranges,
      },
    };
  }
}
