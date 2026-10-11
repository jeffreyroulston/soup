import 'curated_pack.dart';
import 'curated_packs.g.dart';
import 'models.dart';

/// Port of apps/web/app/utils/curatedCollections.ts.
class MatchedPack {
  const MatchedPack(this.pack, this.items, this.score);
  final CuratedPack pack;
  final List<CatalogItem> items;
  final int score;

  CuratedCollection toCollection() => CuratedCollection(
    id: pack.id,
    title: pack.title,
    description: pack.description,
    items: items,
    theme: pack.theme,
  );
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String _providerKey(String kind, String value) =>
    '$kind:${value.trim().toLowerCase()}';

String _titleYear(String name, int? year) =>
    '${_normalize(name)}::${year ?? ''}';

bool isPackInSeason(CuratedPack pack, [DateTime? date]) {
  final season = pack.season;
  if (season == null) return true;
  date ??= DateTime.now();
  final value = date.month * 100 + date.day;
  final start = season.startMonth * 100 + season.startDay;
  final end = season.endMonth * 100 + season.endDay;
  if (start <= end) return value >= start && value <= end;
  return value >= start || value <= end;
}

CuratedPack? getCuratedPack(String id) {
  for (final p in curatedPacks) {
    if (p.id == id) return p;
  }
  return null;
}

List<MatchedPack> matchCuratedCollections(
  List<CatalogItem> library, {
  DateTime? now,
}) {
  now ??= DateTime.now();
  final byProvider = <String, CatalogItem>{};
  final byTitleYear = <String, CatalogItem>{};
  for (final item in library) {
    item.providerIds.forEach((rawKey, value) {
      final key = rawKey.toLowerCase();
      if (key == 'imdb' || key == 'imdbid') {
        byProvider.putIfAbsent(_providerKey('imdb', value), () => item);
      }
      if (key == 'tmdb' || key == 'tmdbid') {
        byProvider.putIfAbsent(_providerKey('tmdb', value), () => item);
      }
    });
    byTitleYear[_titleYear(item.name, item.productionYear)] = item;
    byTitleYear.putIfAbsent(_titleYear(item.name, null), () => item);
  }

  CatalogItem? matchEntry(PackEntry e) {
    if (e.imdb != null) {
      final hit = byProvider[_providerKey('imdb', e.imdb!)];
      if (hit != null) return hit;
    }
    if (e.tmdb != null) {
      final hit = byProvider[_providerKey('tmdb', e.tmdb!)];
      if (hit != null) return hit;
    }
    final exact = byTitleYear[_titleYear(e.name, e.year)];
    if (exact != null) return exact;
    if (e.year == null) return byTitleYear[_titleYear(e.name, null)];
    return null;
  }

  final matched = <MatchedPack>[];
  for (final pack in curatedPacks) {
    if (pack.season != null && !isPackInSeason(pack, now)) continue;
    final seen = <String>{};
    final items = <CatalogItem>[];
    for (final entry in pack.entries) {
      final hit = matchEntry(entry);
      if (hit == null || !seen.add(hit.id)) continue;
      items.add(hit);
    }
    if (items.length < pack.minMatches) continue;
    final waveBonus = pack.wave == 'a'
        ? 30
        : pack.wave == 'b'
        ? 15
        : 0;
    final seasonBonus = pack.season != null ? 100 : 0;
    matched.add(
      MatchedPack(pack, items, seasonBonus + waveBonus + items.length * 2),
    );
  }
  matched.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : b.items.length.compareTo(a.items.length);
  });
  return matched;
}

MatchedPack? matchCuratedPack(
  CuratedPack pack,
  List<CatalogItem> library, [
  DateTime? now,
]) {
  if (pack.season != null && !isPackInSeason(pack, now)) return null;
  for (final m in matchCuratedCollections(library, now: now)) {
    if (m.pack.id == pack.id) return m;
  }
  return null;
}
