import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/error_state.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import 'history_screen.dart';
import 'my_stuff_tabs.dart';

/// Touch history: My Stuff tabs, then the day-grouped list with a round
/// watched toggle on each row.
class TouchHistoryScreen extends StatefulWidget {
  const TouchHistoryScreen({super.key});

  @override
  State<TouchHistoryScreen> createState() => _TouchHistoryScreenState();
}

class _TouchHistoryScreenState extends State<TouchHistoryScreen>
    with HistoryToggles<TouchHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final catalog = SoupScope.of(context).catalog;
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.history(),
      builder: (context, loaded, error) {
        final items = loaded == null ? null : mergeHistory(loaded);
        final now = DateTime.now();
        return TouchScaffold(
          section: NavSection.myStuff,
          title: 'My Stuff',
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  TouchSpacing.gutter,
                  8,
                  TouchSpacing.gutter,
                  20,
                ),
                child: TouchMyStuffTabs(current: MyStuffTab.history),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TouchSpacing.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recently watched',
                      style: SoupType.style(
                        size: 22,
                        weight: 800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      historyNote,
                      style: SoupType.style(
                        size: 14,
                        weight: 600,
                        color: SoupColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (items == null && error != null)
              SliverToBoxAdapter(child: ErrorState(error: error))
            else if (items == null)
              SliverToBoxAdapter(child: _skeleton())
            else if (items.isEmpty)
              SliverToBoxAdapter(child: _empty())
            else
              for (final group in groupHistory(items, now))
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          TouchSpacing.gutter,
                          22,
                          TouchSpacing.gutter,
                          6,
                        ),
                        child: Text(
                          group.label.toUpperCase(),
                          style: SoupType.style(
                            size: 12,
                            weight: 800,
                            letterSpacing: 1,
                            color: SoupColors.muted,
                          ),
                        ),
                      ),
                      for (final item in group.rows)
                        _TouchHistoryRow(
                          key: ValueKey(item.id),
                          item: item,
                          when: historyWhen(context, item, now),
                          onToggle: () => togglePlayed(catalog, item),
                        ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _skeleton() => Padding(
    padding: const EdgeInsets.fromLTRB(
      TouchSpacing.gutter,
      24,
      TouchSpacing.gutter,
      0,
    ),
    child: Column(
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            height: 64,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: SoupColors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(SoupRadii.card),
            ),
          ),
      ],
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.fromLTRB(
      TouchSpacing.gutter,
      24,
      TouchSpacing.gutter,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nothing watched yet',
          style: SoupType.style(size: 20, weight: 800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Movies and episodes you finish will show up here.',
          style: SoupType.style(size: 15, color: SoupColors.muted),
        ),
        const SizedBox(height: 16),
        TouchButton(
          label: 'Browse Home',
          primary: false,
          onPressed: () => openHome(context),
        ),
      ],
    ),
  );
}

class _TouchHistoryRow extends StatelessWidget {
  const _TouchHistoryRow({
    required this.item,
    required this.when,
    required this.onToggle,
    super.key,
  });

  final CatalogItem item;
  final String when;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final detail = [...historyDetail(item), when].join('   ');
    return Opacity(
      opacity: item.played ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
        decoration: BoxDecoration(
          color: item.played ? null : SoupColors.surface,
          borderRadius: BorderRadius.circular(SoupRadii.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Focusable(
                scale: 1.0,
                onActivate: () => openItem(context, item),
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 96,
                          height: 54,
                          child: CatalogImage(
                            image: item.landscape,
                            maxWidth: 240,
                            fallbackTitle: item.name,
                            fallbackFontSize: 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SoupType.style(size: 16, weight: 800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SoupType.style(
                                size: 13,
                                weight: 600,
                                color: SoupColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            TouchIconButton(
              icon: Icons.check_rounded,
              size: 40,
              filled: item.played,
              tooltip: item.played
                  ? 'Mark ${item.name} unwatched'
                  : 'Mark ${item.name} watched',
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}
