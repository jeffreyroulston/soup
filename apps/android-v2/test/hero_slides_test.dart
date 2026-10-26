import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/features/home/home_screen.dart';

final _now = DateTime(2026, 10, 14);
DateTime _daysAgo(int d) => _now.subtract(Duration(days: d));

CatalogItem _ep(String id, String series, int s, int e, int addedDaysAgo) =>
    CatalogItem(
      id: id,
      name: id,
      type: 'Episode',
      seriesId: series,
      parentIndexNumber: s,
      indexNumber: e,
      backdropImageTag: 'b',
      dateAdded: _daysAgo(addedDaysAgo),
    );

CatalogItem _movie(String id, [int? addedDaysAgo]) => CatalogItem(
  id: id,
  name: id,
  type: 'Movie',
  backdropImageTag: 'b',
  dateAdded: addedDaysAgo == null ? null : _daysAgo(addedDaysAgo),
);

void main() {
  test('hero: new season, new episode, continue, recently added, random', () {
    final home = HomeData(
      resume: [_movie('resume')],
      nextUp: [
        _ep('new-ep', 'A', 1, 5, 2),
        _ep('old-ep', 'B', 1, 3, 200), // not new: skipped
        _ep('new-season', 'C', 2, 1, 3),
      ],
      recentlyAdded: [
        Shelf(
          title: 'Movies',
          items: [_movie('old-add', 90), _movie('add-1', 5)],
        ),
        Shelf(title: 'TV', items: [_movie('add-0', 1)]),
      ],
      random: [_movie('resume'), _movie('rand')],
    );
    final ids = [
      for (final s in HomeScreen.heroSlides(home, now: _now)) s.item.id,
    ];
    expect(ids, ['new-season', 'new-ep', 'resume', 'add-0', 'add-1', 'rand']);
  });
}
