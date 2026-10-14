import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/error_state.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/soup_button.dart';
import 'history_screen_touch.dart';
import 'my_stuff_tabs.dart';

const historyNote = 'Marking something unwatched puts it back in Next Up';

class HistoryGroup {
  HistoryGroup(this.label);
  final String label;
  final rows = <CatalogItem>[];
}

DateTime? _played(CatalogItem item) =>
    DateTime.tryParse(item.lastPlayedDate ?? '')?.toLocal();

int _daysAgo(DateTime date, DateTime now) => DateTime(
  now.year,
  now.month,
  now.day,
).difference(DateTime(date.year, date.month, date.day)).inDays;

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Today, Yesterday, Earlier this week, then by month (with the year when
/// it isn't this one). [items] arrive newest first.
List<HistoryGroup> groupHistory(List<CatalogItem> items, DateTime now) {
  String label(CatalogItem item) {
    final date = _played(item);
    if (date == null) return 'Earlier';
    final days = _daysAgo(date, now);
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Earlier this week';
    final month = _months[date.month - 1];
    return date.year == now.year ? month : '$month ${date.year}';
  }

  final groups = <HistoryGroup>[];
  for (final item in items) {
    final l = label(item);
    if (groups.isEmpty || groups.last.label != l) groups.add(HistoryGroup(l));
    groups.last.rows.add(item);
  }
  return groups;
}

/// A time for today and yesterday, a weekday this week, a date before that.
String historyWhen(BuildContext context, CatalogItem item, DateTime now) {
  final date = _played(item);
  if (date == null) return '';
  final days = _daysAgo(date, now);
  if (days <= 1) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
  if (days < 7) return _weekdays[date.weekday - 1];
  return '${date.day} ${_months[date.month - 1].substring(0, 3)}';
}

/// "Signal Drift", "S1, E2" for an episode; "Movie", "2019" for a film.
List<String> historyDetail(CatalogItem item) {
  if (item.type == 'Episode') {
    final s = item.parentIndexNumber;
    final e = item.indexNumber;
    final code = s != null && e != null
        ? 'S$s, E$e'
        : (e != null ? 'E$e' : null);
    return [?item.seriesName, ?code];
  }
  return ['Movie', if (item.productionYear != null) '${item.productionYear}'];
}

/// Watched toggles made on this visit. Marking something unwatched drops it
/// from the server's list and marking it watched again re-dates it to now,
/// so the row keeps its place (dimmed) until the page is left.
mixin HistoryToggles<T extends StatefulWidget> on State<T> {
  final _toggled = <String, ({CatalogItem original, bool played})>{};

  List<CatalogItem> mergeHistory(List<CatalogItem> loaded) {
    final ids = {for (final i in loaded) i.id};
    final rows = [
      for (final i in loaded)
        if (_toggled[i.id] case final t?)
          t.original.copyWith(played: t.played)
        else
          i,
      for (final MapEntry(:key, :value) in _toggled.entries)
        if (!ids.contains(key)) value.original.copyWith(played: value.played),
    ];
    return rows..sort(
      (a, b) => (b.lastPlayedDate ?? '').compareTo(a.lastPlayedDate ?? ''),
    );
  }

  void togglePlayed(Catalog catalog, CatalogItem item) {
    final original = _toggled[item.id]?.original ?? item;
    setState(
      () => _toggled[item.id] = (original: original, played: !item.played),
    );
    catalog.setPlayed(item.id, !item.played).catchError((Object _) {
      if (mounted) setState(() => _toggled.remove(item.id));
    });
  }
}

/// Web `pages/history.vue`: the My Stuff tab of finished movies and
/// episodes, grouped by day, each with a watched toggle.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with HistoryToggles<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return const TouchHistoryScreen();
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.history(),
      builder: (context, loaded, error) {
        final items = loaded == null ? null : mergeHistory(loaded);
        return PageScaffold(
          section: NavSection.myStuff,
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: SoupSpacing.gutter,
              ),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: _content(items, error),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(
      SoupSpacing.gutter,
      120,
      SoupSpacing.gutter,
      28,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MyStuffHeader(current: MyStuffTab.history),
        const SizedBox(height: 32),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 14,
          children: [
            Text(
              'Recently watched',
              style: SoupType.style(size: 28, weight: 800, letterSpacing: -0.5),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                historyNote,
                style: SoupType.style(
                  size: 16,
                  weight: 600,
                  color: SoupColors.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _content(List<CatalogItem>? items, Object? error) {
    if (items == null) {
      if (error != null) return ErrorState(error: error);
      return Column(
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              height: 96,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: SoupColors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(SoupRadii.card),
              ),
            ),
        ],
      );
    }
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing watched yet',
            style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Movies and episodes you finish will show up here.',
            style: SoupType.style(size: 17, color: SoupColors.muted),
          ),
          const SizedBox(height: 22),
          SoupButton(
            label: 'Browse Home',
            autofocus: true,
            height: 48,
            style: SoupButtonStyle.glass,
            onPressed: () => openHome(context),
          ),
        ],
      );
    }
    final catalog = SoupScope.of(context).catalog;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groupHistory(items, now)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Text(
              group.label.toUpperCase(),
              style: SoupType.style(
                size: 14,
                weight: 800,
                letterSpacing: 1,
                color: SoupColors.muted,
              ),
            ),
          ),
          for (final item in group.rows)
            _HistoryRow(
              key: ValueKey(item.id),
              item: item,
              when: historyWhen(context, item, now),
              autofocus: item.id == items.first.id,
              onToggle: () => togglePlayed(catalog, item),
            ),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.when,
    required this.onToggle,
    this.autofocus = false,
    super.key,
  });

  final CatalogItem item;
  final String when;
  final VoidCallback onToggle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final detail = historyDetail(item);
    return Opacity(
      opacity: item.played ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: item.played ? null : SoupColors.surface,
          borderRadius: BorderRadius.circular(SoupRadii.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Focusable(
                autofocus: autofocus,
                scale: 1.0,
                onActivate: () => openItem(context, item),
                builder: (context, focused) => Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: focused ? const Color(0x14FFFFFF) : null,
                    borderRadius: BorderRadius.circular(SoupRadii.card),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 136,
                          height: 76,
                          child: CatalogImage(
                            image: item.landscape,
                            maxWidth: 320,
                            fallbackTitle: item.name,
                            fallbackFontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SoupType.style(size: 19, weight: 800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail.join('    '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SoupType.style(
                                size: 16,
                                weight: 600,
                                color: SoupColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        when,
                        style:
                            SoupType.style(
                              size: 16,
                              weight: 600,
                              color: SoupColors.muted,
                            ).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 264,
              child: SoupButton(
                label: item.played ? 'Mark unwatched' : 'Mark watched',
                height: 48,
                style: SoupButtonStyle.glass,
                onPressed: onToggle,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
