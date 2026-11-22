import 'package:flutter/widgets.dart';

import '../../data/seerr_models.dart';
import '../explore/seerr_builder.dart';

/// Web `pages/search.vue`'s Seerr half: TMDB matches for [term] that aren't
/// (even partly) in the library, since those already show up as Jellyfin
/// results. Empty when Seerr isn't set up, can't be reached or fails, so
/// search never errors on its account.
class SeerrMatches extends StatelessWidget {
  const SeerrMatches({required this.term, required this.builder, super.key});
  final String term;

  /// `titles` is null while Seerr is still answering.
  final Widget Function(BuildContext context, List<SeerrTitle>? titles) builder;

  @override
  Widget build(BuildContext context) => SeerrBuilder<List<SeerrTitle>>(
    load: (seerr) async {
      if (term.isEmpty) return const [];
      final status = await seerr.loadStatus();
      if (!status.usable) return const [];
      final results = await seerr.search(term);
      return [
        for (final t in results.titles)
          if (!isInLibrary(t.mediaInfo)) t,
      ];
    },
    keys: [term],
    builder: (context, titles, error) =>
        builder(context, error != null ? const [] : titles),
  );
}
