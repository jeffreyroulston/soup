import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/soup_text_field.dart';
import '../../ui/widgets/error_state.dart';
import '../explore/seerr_card.dart';
import 'search_scope.dart';
import 'seerr_matches.dart';

/// Touch search: field and scope pills up top, then result rails once there
/// is a query.
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
  SearchScope _scope = SearchScope.all;
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
            child: PillTabs<SearchScope>(
              options: SearchScope.values,
              value: _scope,
              labelOf: (s) => s.label,
              onChanged: (s) => setState(() => _scope = s),
              height: 38,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _term.isEmpty && _person == null
                ? const SizedBox.shrink()
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

  Widget _gap(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 28), child: child);

  Widget _message(String text, {Color color = SoupColors.muted}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
    child: Text(text, style: SoupType.style(size: 15, color: color)),
  );

  @override
  Widget build(BuildContext context) => SeerrMatches(
    term: term,
    builder: (context, seerrMatches) => CatalogBuilder<SearchResults>(
      load: (c) => c.search(term),
      keys: [term],
      builder: (context, results, error) {
        final items = results?.items ?? const <CatalogItem>[];
        final titles = scope.titles(items);
        final episodes = SearchScope.episodes(items);
        final people = results?.people ?? const <Person>[];
        final requestable = scope.seerrTitles(seerrMatches ?? const []);
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
              if (scope.showsTitles && titles.isNotEmpty)
                _gap(TouchRow(title: 'Movies & Shows', items: titles)),
              if (scope.showsEpisodes && episodes.isNotEmpty)
                _gap(
                  TouchRow(
                    title: 'Episodes',
                    items: episodes,
                    shape: CardShape.landscape,
                  ),
                ),
              if (requestable.isNotEmpty)
                _gap(
                  TouchSeerrRow(
                    title: 'Not in Your Library',
                    titles: requestable,
                  ),
                ),
              if (scope.showsPeople && people.isNotEmpty)
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
              if (items.isEmpty &&
                  people.isEmpty &&
                  (seerrMatches?.isEmpty ?? false))
                _message('No results for “$term”.'),
            ],
          ],
        );
      },
    ),
  );
}
