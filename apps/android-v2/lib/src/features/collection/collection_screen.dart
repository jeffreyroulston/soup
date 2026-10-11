import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/page_scaffold.dart';

/// Web `pages/collection/[id].vue`: a curated pack's matched titles.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({required this.packId, super.key});
  final String packId;

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<CuratedCollection?>(
      load: (c) => c.curatedCollection(packId),
      keys: [packId],
      builder: (context, collection, error) {
        final loading = collection == null && error == null;
        return PageScaffold(
          section: NavSection.none,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SoupSpacing.gutter,
                120,
                SoupSpacing.gutter,
                28,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection?.title ?? (loading ? '' : 'Collection'),
                      style: SoupType.style(
                        size: 56,
                        weight: 800,
                        letterSpacing: -2.5,
                        height: 1,
                      ),
                    ),
                    if (collection != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        collection.countLabel,
                        style: SoupType.style(
                          size: 16,
                          weight: 600,
                          color: SoupColors.muted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(
                          collection.description,
                          style: SoupType.style(
                            size: 17,
                            color: SoupColors.ink2,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                    if (collection == null && !loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          "This collection isn't available — not enough matching titles in your library, or it's out of season.",
                          style: SoupType.style(
                            size: 17,
                            color: SoupColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: SoupSpacing.gutter,
                vertical: 12,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 28,
                  crossAxisSpacing: 20,
                  childAspectRatio: 0.56,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: collection?.items.length ?? (loading ? 12 : 0),
                  (context, i) => collection == null
                      ? const MediaCardSkeleton()
                      : MediaCard(item: collection.items[i], autofocus: i == 0),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
