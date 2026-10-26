import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soup_core/soup_core.dart';

/// Port of apps/web/app/composables/usePlaybackPrefs.ts. Persisted locally;
/// the language choices also sync to the Jellyfin account (see
/// [syncLanguages]) so they follow the user to every device.
class PlaybackPrefs extends ChangeNotifier {
  PlaybackPrefs({SharedPreferencesAsync? store}) : _store = store;

  SharedPreferencesAsync? _store;
  SharedPreferencesAsync get _s => _store ??= SharedPreferencesAsync();

  bool autoplayNext = true;
  bool autoSkipIntros = false;

  /// Quality cap in bits/s; null = Auto.
  int? maxBitrate;

  /// ISO 639-2 code; null = file default.
  String? audioLanguage;

  /// ISO 639-2 code; null = subtitles off.
  String? subtitleLanguage;

  bool loaded = false;
  Future<void>? _loading;

  /// Saves language changes to the account; set once signed in.
  Future<void> Function(JellyfinLanguagePreferences)? _saveLanguages;

  JellyfinLanguagePreferences get _languages => JellyfinLanguagePreferences(
    audioLanguage: audioLanguage,
    subtitleLanguage: subtitleLanguage,
  );

  static const languages = <(String, String)>[
    ('eng', 'English'),
    ('ara', 'Arabic'),
    ('chi', 'Chinese'),
    ('dan', 'Danish'),
    ('dut', 'Dutch'),
    ('fin', 'Finnish'),
    ('fre', 'French'),
    ('ger', 'German'),
    ('hin', 'Hindi'),
    ('ita', 'Italian'),
    ('jpn', 'Japanese'),
    ('kor', 'Korean'),
    ('nor', 'Norwegian'),
    ('pol', 'Polish'),
    ('por', 'Portuguese'),
    ('rus', 'Russian'),
    ('spa', 'Spanish'),
    ('swe', 'Swedish'),
    ('tur', 'Turkish'),
  ];

  /// Quality caps offered in the player and Settings; Jellyfin picks the
  /// resolution to fit the bitrate. See QUALITY_CAPS in web utils/media.ts,
  /// and qualityCapsFor for the ones a given file offers.
  static const qualityCaps =
      <({int bitrate, int height, String label, String detail})>[
        (bitrate: 120000000, height: 2160, label: '4K', detail: '120 Mbps'),
        (bitrate: 80000000, height: 2160, label: '4K', detail: '80 Mbps'),
        (bitrate: 60000000, height: 2160, label: '4K', detail: '60 Mbps'),
        (bitrate: 40000000, height: 2160, label: '4K', detail: '40 Mbps'),
        (bitrate: 20000000, height: 1080, label: '1080p', detail: '20 Mbps'),
        (bitrate: 15000000, height: 1080, label: '1080p', detail: '15 Mbps'),
        (bitrate: 10000000, height: 1080, label: '1080p', detail: '10 Mbps'),
        (bitrate: 8000000, height: 1080, label: '1080p', detail: '8 Mbps'),
        (bitrate: 6000000, height: 720, label: '720p', detail: '6 Mbps'),
        (bitrate: 4000000, height: 720, label: '720p', detail: '4 Mbps'),
        (bitrate: 3000000, height: 480, label: '480p', detail: '3 Mbps'),
        (bitrate: 1500000, height: 480, label: '480p', detail: '1.5 Mbps'),
        (bitrate: 1000000, height: 360, label: '360p', detail: '1 Mbps'),
      ];

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      autoplayNext = await _s.getBool('pp.autoplayNext') ?? true;
      autoSkipIntros = await _s.getBool('pp.autoSkipIntros') ?? false;
      maxBitrate = await _s.getInt('pp.maxBitrate');
      audioLanguage = await _s.getString('pp.audioLanguage');
      subtitleLanguage = await _s.getString('pp.subtitleLanguage');
    } on Object {
      // Defaults apply for this run.
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> update({
    bool? autoplayNext,
    bool? autoSkipIntros,
    Object? maxBitrate = _keep,
    Object? audioLanguage = _keep,
    Object? subtitleLanguage = _keep,
  }) async {
    if (autoplayNext != null) this.autoplayNext = autoplayNext;
    if (autoSkipIntros != null) this.autoSkipIntros = autoSkipIntros;
    if (!identical(maxBitrate, _keep)) this.maxBitrate = maxBitrate as int?;
    final languagesBefore = (this.audioLanguage, this.subtitleLanguage);
    if (!identical(audioLanguage, _keep)) {
      this.audioLanguage = audioLanguage as String?;
    }
    if (!identical(subtitleLanguage, _keep)) {
      this.subtitleLanguage = subtitleLanguage as String?;
    }
    notifyListeners();
    final save = _saveLanguages;
    if (save != null &&
        languagesBefore != (this.audioLanguage, this.subtitleLanguage)) {
      unawaited(
        save(_languages).catchError((Object error) {
          debugPrint('[soup] could not save languages to Jellyfin: $error');
        }),
      );
    }
    try {
      await _s.setBool('pp.autoplayNext', this.autoplayNext);
      await _s.setBool('pp.autoSkipIntros', this.autoSkipIntros);
      await _persist('pp.maxBitrate', this.maxBitrate);
      await _persist('pp.audioLanguage', this.audioLanguage);
      await _persist('pp.subtitleLanguage', this.subtitleLanguage);
    } on Object {
      // Applies for this run even if storage is unavailable.
    }
  }

  /// Adopts the account's languages, or seeds the account from this device
  /// when it has none yet, then saves later changes back to it.
  Future<void> syncLanguages({
    required Future<JellyfinLanguagePreferences> Function() fetch,
    required Future<void> Function(JellyfinLanguagePreferences) save,
  }) async {
    await load();
    _saveLanguages = save;
    final account = await fetch();
    final accountEmpty =
        account.audioLanguage == null && account.subtitleLanguage == null;
    if (accountEmpty) {
      if (audioLanguage != null || subtitleLanguage != null) {
        await save(_languages);
      }
      return;
    }
    if (account.audioLanguage == audioLanguage &&
        account.subtitleLanguage == subtitleLanguage) {
      return;
    }
    _saveLanguages = null; // Don't echo the account's own values back.
    await update(
      audioLanguage: account.audioLanguage,
      subtitleLanguage: account.subtitleLanguage,
    );
    _saveLanguages = save;
  }

  Future<void> _persist(String key, Object? value) async {
    if (value == null) {
      await _s.remove(key);
    } else if (value is int) {
      await _s.setInt(key, value);
    } else if (value is String) {
      await _s.setString(key, value);
    }
  }

  static const Object _keep = Object();
}
