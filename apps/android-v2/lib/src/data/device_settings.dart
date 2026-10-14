import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soup_core/soup_core.dart';

import 'soup_device.dart';

/// Settings that belong to this device rather than the account: its name in
/// Jellyfin and how audio reaches its speakers. Stored locally, so the living
/// room TV and a phone keep their own.
class DeviceSettings extends ChangeNotifier {
  DeviceSettings({required this.device, SharedPreferencesAsync? store})
    : _store = store;

  final SoupDevice device;
  SharedPreferencesAsync? _store;
  SharedPreferencesAsync get _s => _store ??= SharedPreferencesAsync();

  /// Name the user typed; null uses [SoupDevice.detectedName].
  String? customName;
  AudioOutputMode audioOutput = AudioOutputMode.auto;

  String get name => customName ?? device.detectedName;

  /// What Jellyfin receives as the `Device` name.
  String get jellyfinName => JellyfinApi.headerSafeDeviceName(name);

  static const audioOutputOptions = <(AudioOutputMode, String, String)>[
    (AudioOutputMode.auto, 'Auto', 'What this device reports'),
    (AudioOutputMode.stereo, 'Stereo', 'Downmix to 2 channels'),
    (AudioOutputMode.surround, 'Surround', 'Dolby Digital 5.1'),
    (AudioOutputMode.passthrough, 'Passthrough', 'TrueHD, DTS to a receiver'),
  ];

  JellyfinDeviceProfile profile() => JellyfinDeviceProfile(
    capabilities: device.capabilities,
    audioOutput: audioOutput,
    name: jellyfinName,
  );

  Future<void> load() async {
    try {
      final saved = (await _s.getString('device.name'))?.trim();
      customName = saved == null || saved.isEmpty ? null : saved;
      audioOutput = AudioOutputMode.parse(
        await _s.getString('device.audioOutput'),
      );
    } on Object {
      // Defaults apply for this run.
    }
    notifyListeners();
  }

  Future<void> update({
    Object? customName = _keep,
    AudioOutputMode? audioOutput,
  }) async {
    if (!identical(customName, _keep)) {
      final trimmed = (customName as String?)?.trim();
      this.customName = trimmed == null || trimmed.isEmpty ? null : trimmed;
    }
    if (audioOutput != null) this.audioOutput = audioOutput;
    notifyListeners();
    try {
      final name = this.customName;
      if (name == null) {
        await _s.remove('device.name');
      } else {
        await _s.setString('device.name', name);
      }
      await _s.setString('device.audioOutput', this.audioOutput.name);
    } on Object {
      // Applies for this run even if storage is unavailable.
    }
  }

  static const Object _keep = Object();
}
