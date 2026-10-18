import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/media_row.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/soup_text_field.dart';
import '../../ui/widgets/error_state.dart';
import 'search_screen_touch.dart';
import 'search_scope.dart';

const _tints = [
  Color(0xFF2541C8),
  Color(0xFF3A0F2A),
  Color(0xFF16353A),
  Color(0xFF5A3B22),
  Color(0xFF1F1A2E),
  Color(0xFF2E5E3B),
];

/// Web `pages/search.vue`.
class SearchScreen extends StatefulWidget {
  const SearchScreen({this.initialQuery, this.initialPerson, super.key});
  final String? initialQuery;
  final Person? initialPerson;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;
  String _term = '';
  SearchScope _scope = SearchScope.all;
  Person? _person;

  @override
  void initState() {
    super.initState();
    _term = (widget.initialQuery ?? '').trim();
    _person = widget.initialPerson;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return TouchSearchScreen(
        initialQuery: widget.initialQuery,
        initialPerson: widget.initialPerson,
      );
    }
    return PageScaffold(
      section: NavSection.search,
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SoupSpacing.gutter,
                  112,
                  SoupSpacing.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SoupTextField(
                      controller: _controller,
                      label: 'Search',
                      hint: 'Movies, shows, people',
                      autofocus: true,
                      onChanged: _changed,
                      onSubmitted: () =>
                          setState(() => _term = _controller.text.trim()),
                    ),
                    const SizedBox(height: 18),
                    PillTabs<SearchScope>(
                      options: SearchScope.values,
                      value: _scope,
                      labelOf: (s) => s.label,
                      onChanged: (s) => setState(() => _scope = s),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 36),
            child: _term.isEmpty && _person == null
                ? const _Browse()
                : _Results(
                    term: _term,
                    scope: _scope,
                    person: _person,
                    onClearPerson: () => setState(() => _person = null),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Browse extends StatelessWidget {
  const _Browse();

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: SizedBox(
        width: 1000,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
          child: CatalogBuilder<List<CatalogItem>>(
            load: (c) => c.libraries(),
            builder: (context, libs, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BROWSE',
                  style: SoupType.style(
                    size: 13,
                    weight: 800,
                    color: SoupColors.muted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < (libs?.length ?? 0); i++)
                      Focusable(
                        radius: SoupRadii.card,
                        onActivate: () => openLibrary(context, libs![i]),
                        builder: (context, focused) => Container(
                          width: 296,
                          height: 96,
                          padding: const EdgeInsets.all(18),
                          alignment: Alignment.bottomLeft,
                          decoration: BoxDecoration(
                            color: _tints[i % _tints.length],
                            borderRadius: BorderRadius.circular(SoupRadii.card),
                          ),
                          child: Text(
                            libs![i].name,
                            style: SoupType.style(size: 22, weight: 800),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Results extends StatelessWidget {
  const _Results({
    required this.term,
    required this.scope,
    required this.person,
    required this.onClearPerson,
  });
  final String term;
  final SearchScope scope;
  final Person? person;
  final VoidCallback onClearPerson;

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<SearchResults>(
      load: (c) => c.search(term),
      keys: [term],
      builder: (context, results, error) {
        final items = results?.items ?? const <CatalogItem>[];
        final titles = scope.titles(items);
        final episodes = SearchScope.episodes(items);
        final top = items.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (person != null)
              CatalogBuilder<List<CatalogItem>>(
                load: (c) => c.personItems(person!.id),
                keys: [person!.id],
                builder: (context, list, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: MediaRow(
                    title: 'Featuring ${person!.name}',
                    items: list ?? const [],
                    loading: list == null,
                    header: Focusable(
                      radius: 18,
                      onActivate: onClearPerson,
                      builder: (context, focused) => Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: focused
                              ? SoupColors.elevated
                              : SoupColors.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'Clear',
                          style: SoupType.style(size: 14, weight: 700),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (term.isEmpty)
              const SizedBox.shrink()
            else if (results == null && error == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoupSpacing.gutter,
                ),
                child: Text(
                  'Searching…',
                  style: SoupType.style(size: 17, color: SoupColors.muted),
                ),
              )
            else if (error != null && results == null)
              ErrorState(error: error)
            else ...[
              if (scope == SearchScope.all && top.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: MediaRow(
                    title: 'Top Results',
                    items: top,
                    shape: CardShape.landscape,
                  ),
                ),
              if (scope.showsTitles && titles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: MediaRow(title: 'Movies & Shows', items: titles),
                ),
              if (scope.showsEpisodes && episodes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: MediaRow(
                    title: 'Episodes',
                    items: episodes,
                    shape: CardShape.landscape,
                  ),
                ),
              if (scope.showsPeople && (results?.people.isNotEmpty ?? false))
                _People(people: results!.people),
              if ((results?.items.isEmpty ?? true) &&
                  (results?.people.isEmpty ?? true))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoupSpacing.gutter,
                  ),
                  child: Text(
                    'No results for “$term”.',
                    style: SoupType.style(size: 17, color: SoupColors.muted),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _People extends StatelessWidget {
  const _People({required this.people});
  final List<Person> people;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
        child: Text(
          'Cast & Crew',
          style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
        ),
      ),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: SoupSpacing.gutter,
          vertical: 12,
        ),
        child: Row(
          children: [
            for (final p in people)
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: PersonCard(person: p),
              ),
          ],
        ),
      ),
    ],
  );
}
