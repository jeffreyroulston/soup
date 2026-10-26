import 'package:flutter_test/flutter_test.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_v2/src/data/device_settings.dart';
import 'package:soup_v2/src/data/soup_device.dart';

void main() {
  group('webOS', () {
    test('model years from both webOS numbering schemes', () {
      expect(SoupDevice.webosYear(10), 2025);
      expect(SoupDevice.webosYear(25), 2025);
      expect(SoupDevice.webosYear(5), 2020);
      expect(SoupDevice.webosYear(4), 2018);
      expect(SoupDevice.webosYear(null), 2020);
    });

    test('a 2025 OLED gets HEVC 10-bit, AV1, HDR10 and Dolby Vision', () {
      final caps = SoupDevice.webosCapabilities({
        'versionMajor': 10,
        'version': '10.2.0',
        'uhd': true,
        'oled': true,
        'hdr10': true,
        'dolbyVision': true,
      });
      expect(caps.platform, 'webOS 10.2.0');
      expect(caps.videoCodecs, containsAll(['hevc', 'av1', 'vp9']));
      expect(caps.hevcMain10, isTrue);
      expect(caps.dolbyVision, isTrue);
      expect(caps.hdr10Plus, isFalse);
      expect(caps.audioDecoders, containsAll(['ac3', 'eac3', 'opus']));
      expect(caps.maxVideoHeight, isEmpty);
    });

    test(
      'a TV whose info can\'t be read still gets 4K HDR, not phone limits',
      () {
        final caps = SoupDevice.webosFallback.capabilities;
        expect(caps.platform, 'webOS');
        expect(caps.hevcMain10, isTrue);
        expect(caps.hdr10, isTrue);
        expect(caps.maxVideoHeight, isEmpty);
        expect(caps.maxAudioChannels, 8);
        expect(caps.audioDecoders, containsAll(['ac3', 'eac3']));
      },
    );

    test('an HD TV is limited to 1080p and has no AV1 before 2021', () {
      final caps = SoupDevice.webosCapabilities({
        'versionMajor': 5,
        'uhd': false,
      });
      expect(caps.videoCodecs, isNot(contains('av1')));
      expect(caps.hevcMain10, isFalse);
      expect(caps.maxVideoHeight['hevc'], 1080);
    });
  });

  test('parses what MediaCapabilities.kt reports', () {
    final caps = SoupDevice.androidCapabilities({
      'platform': 'Android 14',
      'videoCodecs': ['hevc', 'av1'],
      'audioDecoders': ['opus', 'ac3'],
      'audioPassthrough': ['ac3', 'eac3', 'truehd'],
      'passthroughKnown': true,
      'maxAudioChannels': 8,
      'hevcMain10': true,
      'hdr10': true,
      'dolbyVision': false,
      'maxVideoHeight': {'hevc': 2160, 'av1': 0},
    });
    expect(caps.videoCodecs, containsAll(['h264', 'hevc', 'av1']));
    expect(caps.audioDecoders, containsAll(['aac', 'opus', 'ac3']));
    expect(caps.audioPassthrough, {'ac3', 'eac3', 'truehd'});
    expect(caps.maxAudioChannels, 8);
    expect(caps.maxVideoHeight, {'hevc': 2160});
    expect(
      caps.passthroughSummary,
      'Dolby Digital, Dolby Digital Plus, Dolby TrueHD',
    );
  });

  test('device settings name the profile and carry the audio mode', () async {
    final settings = DeviceSettings(
      device: const SoupDevice(
        detectedName: 'LG OLED65C5',
        capabilities: DeviceCapabilities.fallback,
      ),
    );
    expect(settings.jellyfinName, 'LG OLED65C5');
    settings
      ..customName = 'Living room TV'
      ..audioOutput = AudioOutputMode.surround;
    final profile = settings.profile();
    expect(profile.name, 'Living room TV');
    expect(profile.audioOutput, AudioOutputMode.surround);
  });
}
