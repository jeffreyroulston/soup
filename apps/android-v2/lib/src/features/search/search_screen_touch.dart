import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/soup_text_field.dart';
import '../../ui/widgets/error_state.dart';

enum _Scope { all, movies, shows, people }

const _scopeLabels = {
  _Scope.all: 'All',
  _Scope.movies: 'Movies',
  _Scope.shows: 'Shows',
  _Scope.people: 'People',
};

const _tints = [
  Color(0xFF2541C8),
  Color(0xFF3A0F2A),
  Color(0xFF16353A),
  Color(0xFF5A3B22),
  Color(0xFF1F1A2E),
  Color(0xFF2E5E3B),
];

/// Touch search: field and scope pills up top, library tiles until there is
/// a query, then result rails.
class TouchSearchScreen extends StatefulWidget {
  const TouchSearchScreen({this.initialQuery, this.initialPerson, super.key});
  final String? initialQuery;
  final Person? initialPerson;

  @override
  State<TouchSearchScreen> createState() => _TouchSearchScreenState();
}

class _TouchSearchScreenState extends State<TouchSearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;
  late String _term = (widget.initialQuery ?? '').trim();
  _Scope _scope = _Scope.all;
  late Person? _person = widget.initialPerson;

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
    return TouchScaffold(
      section: NavSection.search,
      title: 'Search',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TouchSpacing.gutter,
              8,
              TouchSpacing.gutter,
              0,
            ),
            child: SoupTextField(
              controller: _controller,
              label: 'Search',
              hint: 'Movies, shows, people',
              autofocus: _person == null && _term.isEmpty,
              onChanged: _changed,
              onSubmitted: () =>
                  setState(() => _term = _controller.text.trim()),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              TouchSpacing.gutter,
              12,
              TouchSpacing.gutter,
              0,
            ),
            child: PillTabs<_Scope>(
              options: _Scope.values,
              value: _scope,
              labelOf: (s) => _scopeLabels[s]!,
              onChanged: (s) => setState(() => _scope = s),
              height: 38,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
    child: CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.libraries(),
      builder: (context, libs, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BROWSE',
            style: SoupType.style(
              size: 12,
              weight: 800,
              color: SoupColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 600 ? 3 : 2;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < (libs?.length ?? 0); i++)
                    Focusable(
                      radius: SoupRadii.card,
                      onActivate: () => openLibrary(context, libs![i]),
                      builder: (context, _) => Container(
                        width: width,
                        height: 84,
                        padding: const EdgeInsets.all(14),
                        alignment: Alignment.bottomLeft,
                        decoration: BoxDecoration(
                          color: _tints[i % _tints.length],
                          borderRadius: BorderRadius.circular(SoupRadii.card),
                        ),
                        child: Text(
                          libs![i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SoupType.style(size: 18, weight: 800),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
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
  final _Scope scope;
  final Person? person;
  final VoidCallback onClearPerson;

  Widget _gap(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 28), child: child);

  Widget _message(String text, {Color color = SoupColors.muted}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
    child: Text(text, style: SoupType.style(size: 15, color: color)),
  );

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<SearchResults>(
      load: (c) => c.search(term),
      keys: [term],
      builder: (context, results, error) {
        final items = results?.items ?? const <CatalogItem>[];
        final titles = [
          for (final i in items)
            if (switch (scope) {
              _Scope.movies => i.type == 'Movie',
              _Scope.shows => i.type == 'Series',
              _ => i.type == 'Movie' || i.type == 'Series',
            })
              i,
        ];
        final episodes = [
          for (final i in items)
            if (i.type == 'Episode') i,
        ];
        final people = results?.people ?? const <Person>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (person != null)
              CatalogBuilder<List<CatalogItem>>(
                load: (c) => c.personItems(person!.id),
                keys: [person!.id],
                builder: (context, list, _) => _gap(
                  TouchRow(
                    title: 'Featuring ${person!.name}',
                    items: list ?? const [],
                    loading: list == null,
                    trailing: TextButton(
                      onPressed: onClearPerson,
                      child: Text(
                        'Clear',
                        style: SoupType.style(
                          size: 14,
                          weight: 700,
                          color: SoupColors.ink2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (term.isEmpty)
              const SizedBox.shrink()
            else if (results == null && error == null)
              _message('Searching…')
            else if (error != null && results == null)
              ErrorState(error: error)
            else ...[
              if (scope != _Scope.people && titles.isNotEmpty)
                _gap(TouchRow(title: 'Movies & Shows', items: titles)),
              if (scope == _Scope.all && episodes.isNotEmpty)
                _gap(
                  TouchRow(
                    title: 'Episodes',
                    items: episodes,
                    shape: CardShape.landscape,
                  ),
                ),
              if ((scope == _Scope.all || scope == _Scope.people) &&
                  people.isNotEmpty)
                _gap(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TouchSectionTitle('Cast & Crew'),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: TouchSpacing.gutter,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in people)
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: PersonCard(person: p, size: 76),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (items.isEmpty && people.isEmpty)
                _message('No results for “$term”.'),
            ],
          ],
        );
      },
    );
  }
}
