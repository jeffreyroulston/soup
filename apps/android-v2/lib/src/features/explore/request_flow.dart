import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';

/// Making a request from a title page, shared by the TV and touch screens:
/// a movie goes straight through; a show opens the season picker first.
class RequestFlow extends ChangeNotifier {
  bool busy = false;
  String? error;
  bool picking = false;
  final selected = <int>{};

  /// Seasons Seerr doesn't already have or have on the way.
  static List<SeerrSeason> requestable(SeerrDetails details) => [
    for (final s in details.seasons)
      if (seasonStatus(details.mediaInfo, s.seasonNumber) == null) s,
  ];

  /// What the main button does: request a movie, or start picking seasons
  /// (one season, or one left, is requested outright).
  Future<void> start(Seerr seerr, SeerrDetails details) async {
    if (busy) return;
    if (!details.isShow) {
      return _submit(seerr, details);
    }
    final open = requestable(details);
    if (open.length <= 1) {
      return _submit(
        seerr,
        details,
        seasons: open.map((s) => s.seasonNumber).toList(),
      );
    }
    picking = true;
    selected
      ..clear()
      ..addAll(open.map((s) => s.seasonNumber));
    error = null;
    notifyListeners();
  }

  void toggle(int seasonNumber) {
    if (!selected.remove(seasonNumber)) selected.add(seasonNumber);
    notifyListeners();
  }

  void cancelPicking() {
    picking = false;
    notifyListeners();
  }

  Future<void> submitSelected(Seerr seerr, SeerrDetails details) {
    final open = requestable(details);
    final all = selected.length == open.length;
    return _submit(
      seerr,
      details,
      seasons: selected.toList()..sort(),
      allSeasons: all && open.length == details.seasons.length,
    );
  }

  Future<void> _submit(
    Seerr seerr,
    SeerrDetails details, {
    List<int>? seasons,
    bool allSeasons = false,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await seerr.createRequest(
        SeerrRequestPayload(
          mediaType: details.mediaType,
          mediaId: details.tmdbId,
          tvdbId: details.tvdbId,
          seasons: seasons,
          allSeasons: allSeasons,
        ),
      );
      picking = false;
    } on SeerrException catch (e) {
      error = e.notLinked
          ? 'No Seerr account is linked to your Jellyfin login. Sign in to '
                'Seerr with Jellyfin once, then try again.'
          : e.message;
    } on Object catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

/// Which seasons to ask for: toggle chips, then Request / Cancel.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    required this.details,
    required this.flow,
    required this.onSubmit,
    this.compact = false,
    super.key,
  });

  final SeerrDetails details;
  final RequestFlow flow;
  final VoidCallback onSubmit;

  /// Phone sizing.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final open = RequestFlow.requestable(details);
    final count = flow.selected.length;
    final height = compact ? 38.0 : 44.0;
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: SoupColors.surface,
        borderRadius: BorderRadius.circular(SoupRadii.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Which seasons?',
            style: SoupType.style(size: compact ? 16 : 19, weight: 800),
          ),
          SizedBox(height: compact ? 10 : 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < open.length; i++)
                _SeasonChip(
                  label: open[i].name,
                  selected: flow.selected.contains(open[i].seasonNumber),
                  autofocus: i == 0 && !compact,
                  height: height,
                  onActivate: () => flow.toggle(open[i].seasonNumber),
                ),
            ],
          ),
          SizedBox(height: compact ? 12 : 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PickerButton(
                label: flow.busy
                    ? 'Requesting…'
                    : count == 0
                    ? 'Pick a season'
                    : count == open.length &&
                          open.length == details.seasons.length
                    ? 'Request all seasons'
                    : 'Request $count ${count == 1 ? 'season' : 'seasons'}',
                primary: true,
                height: height,
                onActivate: count == 0 || flow.busy ? null : onSubmit,
              ),
              _PickerButton(
                label: 'Cancel',
                height: height,
                onActivate: flow.busy ? null : flow.cancelPicking,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onActivate,
    required this.height,
    this.autofocus = false,
  });
  final String label;
  final bool selected;
  final bool autofocus;
  final double height;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    scale: 1.0,
    radius: height,
    onActivate: onActivate,
    semanticsLabel: '$label${selected ? ', selected' : ''}',
    builder: (context, focused) => Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? SoupColors.ink
            : (focused ? SoupColors.glassFocused : SoupColors.elevated),
        borderRadius: BorderRadius.circular(height),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            const Icon(Icons.check_rounded, size: 16, color: SoupColors.canvas),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: SoupType.style(
              size: 14,
              weight: 700,
              color: selected ? SoupColors.canvas : SoupColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.label,
    required this.onActivate,
    required this.height,
    this.primary = false,
  });
  final String label;
  final VoidCallback? onActivate;
  final double height;
  final bool primary;

  @override
  Widget build(BuildContext context) => Focusable(
    scale: 1.0,
    radius: height,
    onActivate: onActivate,
    builder: (context, focused) => Opacity(
      opacity: onActivate == null ? 0.6 : 1,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary
              ? SoupColors.ink
              : (focused ? SoupColors.glassFocused : SoupColors.elevated),
          borderRadius: BorderRadius.circular(height),
        ),
        child: Text(
          label,
          style: SoupType.style(
            size: 15,
            weight: 800,
            color: primary ? SoupColors.canvas : SoupColors.ink,
          ),
        ),
      ),
    ),
  );
}

/// Year, runtime, genres and score for a title's meta line.
List<String> seerrMetaBits(SeerrDetails details) => [
  if (details.year != null) '${details.year}',
  ?runtimeMinutesLabel(details.runtime),
  ...details.genres.take(3),
  if (details.voteAverage != null)
    '★ ${details.voteAverage!.toStringAsFixed(1)}',
];
