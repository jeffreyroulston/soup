import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/models.dart';
import 'form_factor.dart';
import 'features/collection/collection_screen.dart';
import 'features/favourites/favourites_screen.dart';
import 'features/favourites/history_screen.dart';
import 'features/item/item_screen.dart';
import 'features/library/library_screen.dart';
import 'features/playback/playback_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';

PageRoute<T> _route<T>(
  BuildContext context,
  Widget screen, {
  bool fade = false,
  bool page = true,
}) {
  final scope = SoupScope.of(context);
  final wrapped = scope.rewrap(screen);
  // TV pages share one fixed nav bar: the route itself doesn't move, and
  // PageScaffold fades only the content under the bar.
  if (page && !context.isTouch) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => wrapped,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (_, _, _, child) => child,
    );
  }
  if (fade) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => wrapped,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
  return MaterialPageRoute<T>(builder: (_) => wrapped);
}

/// Top-level destinations replace the stack (nav-bar tabs). The root route is
/// kept: it is `AuthenticatedRoot` (Home), which owns the catalog every pushed
/// route shares — removing it would dispose the catalog under them.
void _goTop(BuildContext context, Widget screen) {
  Navigator.of(context).pushAndRemoveUntil(
    _route<void>(context, screen, fade: true),
    (route) => route.isFirst,
  );
}

void openHome(BuildContext context) =>
    Navigator.of(context).popUntil((route) => route.isFirst);

void openLibrary(BuildContext context, CatalogItem library) =>
    _goTop(context, LibraryScreen(library: library));

/// My Stuff opens on Favourites; History is its other tab.
void openFavourites(BuildContext context) =>
    _goTop(context, const FavouritesScreen());

void openHistory(BuildContext context) =>
    _goTop(context, const HistoryScreen());

void openSearch(BuildContext context, {String? query, Person? person}) =>
    _goTop(context, SearchScreen(initialQuery: query, initialPerson: person));

void openSettings(BuildContext context) =>
    _goTop(context, const SettingsScreen());

/// Detail pages stack so Back returns to where you were.
void openItem(BuildContext context, CatalogItem item) {
  final id = item.type == 'Season' && item.seriesId != null
      ? item.seriesId!
      : item.id;
  Navigator.of(context).push(_route<void>(context, ItemScreen(itemId: id)));
}

void openItemId(BuildContext context, String id) =>
    Navigator.of(context).push(_route<void>(context, ItemScreen(itemId: id)));

/// Swaps this detail page for [item]'s: stepping through episodes with
/// Previous/Next shouldn't stack a page per step for Back to unwind.
void replaceItem(BuildContext context, CatalogItem item) => Navigator.of(
  context,
).pushReplacement(_route<void>(context, ItemScreen(itemId: item.id)));

void openCollection(BuildContext context, String id) => Navigator.of(
  context,
).push(_route<void>(context, CollectionScreen(packId: id)));

/// [subtitleIndex]: null = preference, -1 = off. [maxBitrate]: null =
/// preference, 0 = Auto (no cap).
Future<void> openWatch(
  BuildContext context,
  CatalogItem item, {
  bool fromStart = false,
  int? audioIndex,
  int? subtitleIndex,
  int? maxBitrate,
}) {
  final resume = !fromStart && item.playbackPositionTicks >= 100000000;
  return Navigator.of(context).push(
    _route<void>(
      context,
      page: false,
      PlaybackScreen(
        item: item,
        startTicks: resume ? item.playbackPositionTicks : 0,
        audioIndex: audioIndex,
        subtitleIndex: subtitleIndex,
        maxBitrate: maxBitrate,
      ),
    ),
  );
}
