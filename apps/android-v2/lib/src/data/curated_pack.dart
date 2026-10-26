import 'models.dart';

export 'models.dart' show CuratedTheme;

class PackEntry {
  const PackEntry({
    required this.name,
    this.imdb,
    this.tmdb,
    this.year,
    this.type,
  });
  final String name;
  final String? imdb;
  final String? tmdb;
  final int? year;
  final String? type;
}

class PackSeason {
  const PackSeason(this.startMonth, this.startDay, this.endMonth, this.endDay);
  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;
}

class CuratedPack {
  const CuratedPack({
    required this.id,
    required this.title,
    required this.description,
    required this.minMatches,
    required this.wave,
    required this.theme,
    required this.entries,
    this.season,
  });
  final String id;
  final String title;
  final String description;
  final int minMatches;
  final String wave;
  final PackSeason? season;
  final CuratedTheme theme;
  final List<PackEntry> entries;
}
