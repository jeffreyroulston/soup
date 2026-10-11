import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of apps/web/app/composables/usePlaybackPrefs.ts. Persisted locally.
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

  /// (bitrate, label, detail) — see QUALITY_CAPS in utils/media.ts.
  static const qualityCaps = <(int, String, String)>[
    (20000000, '1080p', '20 Mbps'),
    (10000000, '1080p', '10 Mbps'),
    (6000000, '720p', '6 Mbps'),
    (3000000, '480p', '3 Mbps'),
    (1000000, '360p', '1 Mbps'),
  ];

  Future<void> load() async {
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
    if (!identical(audioLanguage, _keep))
      this.audioLanguage = audioLanguage as String?;
    if (!identical(subtitleLanguage, _keep))
      this.subtitleLanguage = subtitleLanguage as String?;
    notifyListeners();
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
