import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:soup_core/soup_core.dart';

import '../platform.dart';

/// This install: what it's called and what it can play. Detected once at
/// startup; the user's name override and audio setting live in PlaybackPrefs.
class SoupDevice {
  const SoupDevice({
    required this.detectedName,
    required this.capabilities,
    this.detectionError,
  });

  /// Android's device name (Settings › About) or the TV model.
  final String detectedName;
  final DeviceCapabilities capabilities;

  /// Why detection fell back to defaults; null when it worked.
  final String? detectionError;

  static const fallback = SoupDevice(
    detectedName: 'Soup',
    capabilities: DeviceCapabilities.fallback,
  );

  static const _channel = MethodChannel(
    'dev.michaelishri.soup/media_capabilities',
  );

  /// A webOS TV whose model info couldn't be read: assume a recent UHD panel
  /// rather than a phone, so 4K HDR still plays directly.
  static final webosFallback = SoupDevice(
    detectedName: 'LG TV',
    capabilities: webosCapabilities(const {}),
  );

  static Future<SoupDevice> detect() async {
    try {
      return isWebos ? await _webos() : await _android();
    } on Object catch (error) {
      debugPrint('[soup] device detection failed: $error');
      final base = isWebos ? webosFallback : fallback;
      return SoupDevice(
        detectedName: base.detectedName,
        capabilities: base.capabilities,
        detectionError: '$error'.split('\n').first,
      );
    }
  }

  static Future<SoupDevice> _android() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getCapabilities',
    );
    if (raw == null) return fallback;
    return SoupDevice(
      detectedName: raw['deviceName'] as String? ?? 'Android',
      capabilities: androidCapabilities(raw),
    );
  }

  static Future<SoupDevice> _webos() async {
    // Ask LG's plugin directly: webOS reports itself as Linux, and
    // DeviceInfoPlugin().deviceInfo then casts its answer to LinuxDeviceInfo
    // and throws.
    final info = (await DeviceInfoPlatform.instance.deviceInfo()).data;
    final model = info['modelName'] as String?;
    return SoupDevice(
      detectedName: model == null || model.isEmpty ? 'LG TV' : 'LG $model',
      capabilities: webosCapabilities(info),
    );
  }

  /// Parses the map `MediaCapabilities.kt` returns.
  @visibleForTesting
  static DeviceCapabilities androidCapabilities(Map<String, Object?> raw) {
    Set<String> strings(String key) => {
      for (final value in raw[key] as List? ?? const []) '$value',
    };
    final heights = raw['maxVideoHeight'] as Map? ?? const {};
    return DeviceCapabilities(
      platform: raw['platform'] as String? ?? 'Android',
      videoCodecs: {'h264', ...strings('videoCodecs')},
      audioDecoders: {'aac', ...strings('audioDecoders')},
      audioPassthrough: strings('audioPassthrough'),
      passthroughKnown: raw['passthroughKnown'] as bool? ?? false,
      maxAudioChannels: (raw['maxAudioChannels'] as num?)?.toInt() ?? 2,
      hevcMain10: raw['hevcMain10'] as bool? ?? false,
      vp9Profile2: raw['vp9Profile2'] as bool? ?? false,
      av1Main10: raw['av1Main10'] as bool? ?? false,
      hdr10: raw['hdr10'] as bool? ?? false,
      hlg: raw['hlg'] as bool? ?? false,
      hdr10Plus: raw['hdr10Plus'] as bool? ?? false,
      dolbyVision: raw['dolbyVision'] as bool? ?? false,
      maxVideoHeight: {
        for (final MapEntry(:key, :value) in heights.entries)
          if (value is num && value > 0) '$key': value.toInt(),
      },
    );
  }

  /// webOS can't query decoders, so capabilities come from the TV's year
  /// (its webOS version) plus the flags LG reports for the panel. The TV
  /// decodes Dolby audio itself and handles eARC passthrough on its own, so
  /// what reaches the receiver isn't visible here.
  @visibleForTesting
  static DeviceCapabilities webosCapabilities(Map<String, Object?> info) {
    final year = webosYear((info['versionMajor'] as num?)?.toInt());
    final uhd = info['uhd'] as bool? ?? true;
    final hdr10 = info['hdr10'] as bool? ?? uhd;
    final version = info['version'] as String?;
    return DeviceCapabilities(
      platform: version == null ? 'webOS' : 'webOS $version',
      videoCodecs: {
        'h264',
        'hevc',
        if (year >= 2017) 'vp9',
        if (year >= 2021 && uhd) 'av1',
      },
      audioDecoders: {
        'aac',
        'mp3',
        'ac3',
        'eac3',
        if (year >= 2020) ...['flac', 'opus', 'vorbis'],
      },
      maxAudioChannels: 8,
      hevcMain10: uhd,
      // UHD panels decode the 10-bit HDR flavours of the codecs they have.
      vp9Profile2: uhd && year >= 2017,
      av1Main10: uhd && year >= 2021,
      hdr10: hdr10,
      hlg: hdr10 && year >= 2017,
      // LG doesn't support HDR10+; those files play as HDR10.
      dolbyVision: info['dolbyVision'] as bool? ?? (info['oled'] == true),
      maxVideoHeight: uhd
          ? const {}
          : const {'h264': 1080, 'hevc': 1080, 'vp9': 1080, 'av1': 1080},
    );
  }

  /// The model year for a webOS major version: older TVs report 1–11
  /// (webOS 5 = 2020, 10 = 2025), newer ones the year itself (25 = 2025).
  @visibleForTesting
  static int webosYear(int? major) {
    if (major == null) return 2020;
    if (major >= 20) return 2000 + major;
    if (major >= 5) return 2015 + major;
    return switch (major) {
      4 => 2018,
      3 => 2016,
      2 => 2015,
      _ => 2014,
    };
  }
}
