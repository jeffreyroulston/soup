import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/media_card.dart';

/// Touch curated collection: title, description and a poster grid.
class TouchCollectionScreen extends StatelessWidget {
  const TouchCollectionScreen({required this.packId, super.key});
  final String packId;

  @override
  Widget build(BuildContext context) {
    // Wrapped in a record so "still loading" (null) differs from "no such
    // collection" ((null,)).
    return CatalogBuilder<(CuratedCollection?,)>(
      load: (c) async => (await c.curatedCollection(packId),),
      keys: [packId],
      builder: (context, result, error) {
        final collection = result?.$1;
        final loading = result == null && error == null;
        return TouchScaffold(
          section: NavSection.none,
          title: collection?.title,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                TouchSpacing.gutter,
                8,
                TouchSpacing.gutter,
                20,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection?.title ?? (loading ? '' : 'Collection'),
                      style: SoupType.style(
                        size: 32,
                        weight: 800,
                        letterSpacing: -1.2,
                        height: 1.05,
                      ),
                    ),
                    if (collection != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        collection.countLabel,
                        style: SoupType.style(
                          size: 14,
                          weight: 600,
                          color: SoupColors.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        collection.description,
                        style: SoupType.style(
                          size: 15,
                          color: SoupColors.ink2,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (collection == null && !loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          "This collection isn't available — not enough matching titles in your library, or it's out of season.",
                          style: SoupType.style(
                            size: 15,
                            color: SoupColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            TouchPosterGrid(
              itemCount: collection?.items.length ?? (loading ? 9 : 0),
              itemBuilder: (context, i, width) => collection == null
                  ? MediaCardSkeleton(width: width)
                  : MediaCard(item: collection.items[i], width: width),
            ),
          ],
        );
      },
    );
  }
}
