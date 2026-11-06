import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/in_page_back.dart';
import '../../ui/widgets/tmdb_image.dart';
import 'seerr_builder.dart';

/// Web `components/ExplorePosterWall.vue`: "Hidden gems", well-rated films
/// with few votes, as a tilted wall of drifting posters. "Surprise me" (or,
/// on touch, a poster) pulls one title forward in place, so skipping to
/// another is one press rather than a page and back.
///
/// On TV the wall itself isn't focusable (drifting targets make poor D-pad
/// stops): the remote works the button, then the reveal's buttons. Back, or
/// moving focus off the reveal, puts the title back.
class HiddenGemsWall extends StatelessWidget {
  const HiddenGemsWall({required this.status, this.touch = false, super.key});

  final SeerrStatus status;

  /// Phone/tablet sizing and tap-to-reveal posters.
  final bool touch;

  /// Seerr discover filters: liked, but not widely seen.
  static const params = {
    'sortBy': 'popularity.desc',
    'voteAverageGte': '7.4',
    'voteCountGte': '150',
    'voteCountLte': '2500',
  };

  /// A different pair of TMDB pages each day keeps the batch fresh.
  static const _pages = 5;

  static Future<List<SeerrTitle>> _load(Seerr seerr) async {
    final day = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    var page = 1 + day % _pages;
    Future<List<SeerrSearchResults>> two(int page) => Future.wait([
      seerr.discover('discover/movies', page: page, params: params),
      seerr.discover('discover/movies', page: page + 1, params: params),
    ]);
    var results = await two(page);
    // A short last page (or a server with fewer results) falls back to the
    // first.
    if (results.first.titles.isEmpty && page > 1) {
      page = 1;
      results = await two(page);
    }
    // TMDB pages can overlap as popularity shifts; keep first sightings.
    final seen = <String>{};
    return [
      for (final r in results)
        for (final t in r.titles)
          if (seen.add(t.key)) t,
    ];
  }

  @override
  Widget build(BuildContext context) => SeerrBuilder<List<SeerrTitle>>(
    load: _load,
    builder: (context, titles, error) {
      if (titles == null && error == null) {
        return _Frame(
          touch: touch,
          child: const ColoredBox(color: _loading),
        );
      }
      final usable = [
        for (final t in titles ?? const <SeerrTitle>[])
          if (t.posterPath != null) t,
      ];
      if (usable.isEmpty) return const SizedBox.shrink();
      return _Wall(all: usable, status: status, touch: touch);
    },
  );

  static const _loading = Color(0x801C1C1E);
}

/// The section's box: full width, fixed height.
class _Frame extends StatelessWidget {
  const _Frame({required this.touch, required this.child});
  final bool touch;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: touch ? 520 : 470,
    width: double.infinity,
    child: ClipRect(child: child),
  );
}

class _Wall extends StatefulWidget {
  const _Wall({required this.all, required this.status, required this.touch});

  /// Every title loaded, library status included (the reveal looks its pick
  /// up here, so a request made from it shows).
  final List<SeerrTitle> all;
  final SeerrStatus status;
  final bool touch;

  @override
  State<_Wall> createState() => _WallState();
}

class _WallState extends State<_Wall> with SingleTickerProviderStateMixin {
  static const _rowCount = 3;
  static const _tilesPerRow = 12;
  static const _rowSeconds = [110, 130, 150];

  /// Titles already offered this run of the app, so "Another" doesn't come
  /// back round to them early.
  static final _seen = <String>[];

  late final Ticker _ticker = createTicker(_tick);
  final _clock = ValueNotifier<Duration>(Duration.zero);
  Duration _base = Duration.zero;

  String? _pickKey;
  int _reveals = 0;
  bool _busy = false;
  String? _error;
  ModalRoute<Object?>? _route;

  final _surpriseFocus = FocusNode(debugLabel: 'surprise me');
  final _primaryFocus = FocusNode(debugLabel: 'gem primary');
  final _anotherFocus = FocusNode(debugLabel: 'gem another');

  bool get _revealing => _pickKey != null;

  SeerrTitle? get _pick {
    final key = _pickKey;
    if (key == null) return null;
    for (final t in widget.all) {
      if (t.key == key) return t;
    }
    return null;
  }

  /// Titles the library doesn't have yet, unless that leaves too few to fill
  /// a wall.
  List<SeerrTitle> get _titles {
    final fresh = [
      for (final t in widget.all)
        if (availabilityLabel(t.mediaInfo) == null) t,
    ];
    return fresh.length >= 18 ? fresh : widget.all;
  }

  /// Titles are dealt round-robin into the rows, so no poster shows in two
  /// rows; a row repeats only its own titles if there aren't enough.
  List<List<SeerrTitle>> get _rows {
    final list = _titles;
    return [
      for (var r = 0; r < _rowCount; r++)
        () {
          var own = [for (var i = r; i < list.length; i += _rowCount) list[i]];
          if (own.isEmpty) own = list;
          final n = math.max(_tilesPerRow, own.length);
          return [for (var i = 0; i < n; i++) own[i % own.length]];
        }(),
    ];
  }

  void _tick(Duration elapsed) => _clock.value = _base + elapsed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _syncTicker();
  }

  /// Drifts unless a title is out or the platform asks for less motion.
  void _syncTicker() {
    final run = !_revealing && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _base = _clock.value;
      _ticker.stop();
    }
  }

  void _show(SeerrTitle title) {
    final wasOut = _revealing;
    _seen
      ..remove(title.key)
      ..add(title.key);
    setState(() {
      _pickKey = title.key;
      _reveals++;
      _error = null;
    });
    if (!wasOut) InPageBack.add(_route, _closeFromBack);
    _syncTicker();
    if (!widget.touch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Keep focus where it is when "Another" was pressed.
        if (mounted && !_anyRevealFocus) _anotherFocus.requestFocus();
      });
    }
  }

  bool get _anyRevealFocus => _primaryFocus.hasFocus || _anotherFocus.hasFocus;

  void _surprise() {
    final list = _titles;
    if (list.isEmpty) return;
    final offered = _seen.toSet();
    var pool = [
      for (final t in list)
        if (!offered.contains(t.key)) t,
    ];
    // Everything's been offered: start over, just not with the one out.
    if (pool.isEmpty) {
      _seen
        ..clear()
        ..addAll([?_pickKey]);
      pool = [
        for (final t in list)
          if (t.key != _pickKey) t,
      ];
    }
    if (pool.isEmpty) pool = list;
    _show(pool[math.Random().nextInt(pool.length)]);
  }

  /// Scrolls the whole section to the middle of the screen, after the
  /// focused button's own reveal scroll has started (so this one wins).
  void _centre(bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _closeFromBack() => _close(fromBack: true);

  /// [refocus]: hand focus back to "Surprise me" (not when the remote has
  /// already moved it elsewhere).
  void _close({bool refocus = true, bool fromBack = false}) {
    if (!_revealing) return;
    if (!fromBack) InPageBack.remove(_closeFromBack);
    setState(() => _pickKey = null);
    _syncTicker();
    if (refocus && !widget.touch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _surpriseFocus.requestFocus();
      });
    }
  }

  Future<void> _request(SeerrTitle title) async {
    if (_busy) return;
    if (title.mediaType != SeerrMediaType.movie) {
      openExploreTitle(context, title.mediaType, title.tmdbId);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Seerr.of(context).createRequest(
        SeerrRequestPayload(
          mediaType: SeerrMediaType.movie,
          mediaId: title.tmdbId,
        ),
      );
    } on SeerrException catch (e) {
      _error = e.notLinked
          ? 'No Seerr account is linked to your Jellyfin login. Sign in to '
                'Seerr with Jellyfin once, then try again.'
          : e.message;
    } on Object catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    InPageBack.remove(_closeFromBack);
    _ticker.dispose();
    _clock.dispose();
    _surpriseFocus.dispose();
    _primaryFocus.dispose();
    _anotherFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.touch;
    final wide = !touch || MediaQuery.sizeOf(context).width >= 600;
    final pick = _pick;
    // TV: arriving anywhere in the section centres all of it, rather than the
    // focused button's minimal reveal leaving the wall half off-screen.
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: touch ? null : _centre,
      child: Semantics(
        container: true,
        label: 'Hidden gems',
        child: _Frame(
          touch: touch,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _drift(touch),
              ..._scrims(wide),
              if (pick != null)
                // Tapping the dimmed wall puts the title back.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                  ),
                ),
              if (pick == null)
                _Copy(
                  touch: touch,
                  wide: wide,
                  focusNode: _surpriseFocus,
                  onSurprise: _surprise,
                )
              else
                _reveal(pick, wide),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drift(bool touch) {
    final tileWidth = touch ? 112.0 : 132.0;
    final gap = touch ? 12.0 : 16.0;
    final rows = _rows;
    Widget wall = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: gap),
          _DriftRow(
            titles: rows[r],
            tileWidth: tileWidth,
            gap: gap,
            clock: _clock,
            seconds: _rowSeconds[r % _rowSeconds.length],
            reverse: r.isOdd,
            onTap: touch ? _show : null,
          ),
        ],
      ],
    );
    // A blur over the whole wall is cheap on phones, not on TV GPUs: TV just
    // dims.
    if (touch) {
      wall = ImageFiltered(
        enabled: _revealing,
        imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: wall,
      );
    }
    return Positioned(
      left: -120,
      right: -120,
      top: -70,
      bottom: -70,
      child: IgnorePointer(
        ignoring: _revealing,
        child: ExcludeFocus(
          child: ExcludeSemantics(
            excluding: !touch,
            child: AnimatedOpacity(
              opacity: _revealing ? 0.3 : 0.75,
              duration: const Duration(milliseconds: 400),
              child: Transform.rotate(
                angle: -6 * math.pi / 180,
                // Rows may run past the box; the section clips them.
                child: OverflowBox(maxHeight: double.infinity, child: wall),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Copy sits on a wash: from the left on wide screens, from the bottom on
  /// phones; the top and bottom edges fade into the page.
  List<Widget> _scrims(bool wide) => [
    Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: wide ? Alignment.centerLeft : Alignment.bottomCenter,
              end: wide ? Alignment.centerRight : Alignment.topCenter,
              colors: [
                SoupColors.canvas,
                SoupColors.canvas.withValues(alpha: 0.75),
                SoupColors.canvas.withValues(alpha: 0),
              ],
              stops: wide ? const [0, 0.3, 0.6] : const [0, 0.35, 0.7],
            ),
          ),
        ),
      ),
    ),
    for (final top in [true, false])
      Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: 64,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  SoupColors.canvas,
                  SoupColors.canvas.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
  ];

  Widget _reveal(SeerrTitle pick, bool wide) {
    final touch = widget.touch;
    final user = widget.status.user;
    final status = availabilityLabel(pick.mediaInfo);
    final canRequest = user != null && user.canRequest(pick.mediaType);
    final gutter = touch ? 16.0 : SoupSpacing.gutter;
    final posterWidth = wide ? (touch ? 170.0 : 200.0) : 104.0;

    final metaStyle = SoupType.style(
      size: touch ? 13 : 16,
      weight: 600,
      color: SoupColors.ink2,
    );
    // The star is an icon: Manrope has no ★, and webOS has no fallback font.
    final meta = [
      if (pick.year != null) Text('${pick.year}', style: metaStyle),
      if (pick.voteAverage != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: touch ? 15 : 18,
              color: SoupColors.ink2,
            ),
            const SizedBox(width: 3),
            Text(pick.voteAverage!.toStringAsFixed(1), style: metaStyle),
          ],
        ),
      if (pick.voteCount != null)
        Text('${_thousands(pick.voteCount!)} votes', style: metaStyle),
    ];

    final info = _Arrive(
      key: ValueKey('info $_reveals'),
      delay: 0.25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'HIDDEN GEM',
            style: SoupType.style(
              size: touch ? 13 : 14,
              weight: 800,
              letterSpacing: 1,
              color: SoupColors.accent,
            ),
          ),
          SizedBox(height: touch ? 6 : 8),
          Text(
            pick.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(
              size: wide ? (touch ? 34 : 44) : 24,
              weight: 800,
              letterSpacing: wide ? -1.5 : -0.8,
              height: 1,
            ),
          ),
          if (meta.isNotEmpty) ...[
            SizedBox(height: touch ? 6 : 10),
            Wrap(
              spacing: touch ? 14 : 18,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: meta,
            ),
          ],
          if (pick.overview != null) ...[
            SizedBox(height: touch ? 6 : 10),
            Text(
              pick.overview!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(
                size: wide ? (touch ? 15 : 17) : 14,
                color: SoupColors.ink2,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );

    final primary = status != null
        ? _Pill(
            focusNode: _primaryFocus,
            touch: touch,
            label: status,
            icon: Icons.check_rounded,
            tone: _PillTone.quiet,
          )
        : canRequest
        ? _Pill(
            focusNode: _primaryFocus,
            touch: touch,
            label: _busy
                ? 'Requesting…'
                : pick.mediaType == SeerrMediaType.movie
                ? 'Request'
                : 'Request seasons',
            icon: Icons.add_rounded,
            tone: _PillTone.accent,
            onPressed: _busy ? null : () => unawaited(_request(pick)),
          )
        : null;

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: touch ? 10 : 12,
          runSpacing: 10,
          children: [
            ?primary,
            _Pill(
              focusNode: _anotherFocus,
              touch: touch,
              label: 'Another',
              icon: Icons.shuffle_rounded,
              tone: _PillTone.ink,
              onPressed: _surprise,
            ),
            _Pill(
              touch: touch,
              label: 'Details',
              tone: _PillTone.glass,
              onPressed: () =>
                  openExploreTitle(context, pick.mediaType, pick.tmdbId),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: SoupType.style(
              size: 14,
              weight: 600,
              color: SoupColors.accent,
            ),
          ),
        ],
        if (!touch) ...[const SizedBox(height: 14), const _BackHint()],
      ],
    );

    final poster = _Arrive(
      key: ValueKey('poster $_reveals'),
      lift: true,
      child: GestureDetector(
        onTap: () => openExploreTitle(context, pick.mediaType, pick.tmdbId),
        child: Container(
          width: posterWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SoupRadii.card),
            border: Border.all(color: SoupColors.faint),
            boxShadow: const [
              BoxShadow(
                color: Color(0xB3000000),
                blurRadius: 60,
                offset: Offset(0, 24),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SoupRadii.card),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: TmdbImage(
                path: pick.posterPath,
                kind: TmdbImageKind.poster,
                fallbackTitle: pick.title,
              ),
            ),
          ),
        ),
      ),
    );

    // Back/Esc and focus moving away (TV) both put the title back; the
    // buttons stay mounted across "Another", so focus survives a reshuffle.
    final body = wide
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              poster,
              SizedBox(width: touch ? 24 : 36),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    info,
                    SizedBox(height: touch ? 14 : 18),
                    actions,
                  ],
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  poster,
                  const SizedBox(width: 16),
                  Expanded(child: info),
                ],
              ),
              const SizedBox(height: 16),
              actions,
            ],
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Focus(
                skipTraversal: true,
                canRequestFocus: false,
                onFocusChange: (has) {
                  // Focus moving to another page (Details) keeps the title
                  // out, so Back from there lands on it again.
                  if (!has && !widget.touch && (_route?.isCurrent ?? true)) {
                    _close(refocus: false);
                  }
                },
                // Up/Down put the title back on the wall (focus returns to
                // Surprise me) instead of leaving the section from the middle
                // of it; Left/Right move between the buttons.
                onKeyEvent: (node, event) {
                  if (event is KeyUpEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key != LogicalKeyboardKey.arrowUp &&
                      key != LogicalKeyboardKey.arrowDown) {
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyDownEvent) _close();
                  return KeyEventResult.handled;
                },
                child: Semantics(
                  liveRegion: true,
                  label: 'Hidden gem: ${pick.title}',
                  child: body,
                ),
              ),
            ),
          ),
        ),
        if (touch)
          Positioned(
            top: 12,
            right: gutter,
            child: _CloseButton(onPressed: _close),
          ),
      ],
    );
  }

  static String _thousands(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

/// One drifting row: the tiles twice over, slid by the clock so the seam
/// loops. Only the transform changes per frame; the row paints once.
class _DriftRow extends StatelessWidget {
  const _DriftRow({
    required this.titles,
    required this.tileWidth,
    required this.gap,
    required this.clock,
    required this.seconds,
    required this.reverse,
    this.onTap,
  });

  final List<SeerrTitle> titles;
  final double tileWidth;
  final double gap;
  final ValueListenable<Duration> clock;
  final int seconds;
  final bool reverse;
  final ValueChanged<SeerrTitle>? onTap;

  @override
  Widget build(BuildContext context) {
    final half = titles.length * (tileWidth + gap);
    final tiles = RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var copy = 0; copy < 2; copy++)
            for (final t in titles)
              Padding(
                padding: EdgeInsets.only(right: gap),
                child: _Tile(
                  title: t,
                  width: tileWidth,
                  onTap: onTap == null ? null : () => onTap!(t),
                ),
              ),
        ],
      ),
    );
    return SizedBox(
      height: tileWidth * 1.5,
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: ValueListenableBuilder<Duration>(
          valueListenable: clock,
          child: tiles,
          builder: (context, elapsed, child) {
            final phase = (elapsed.inMilliseconds / (seconds * 1000)) % 1.0;
            final dx = reverse ? -(1 - phase) * half : -phase * half;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.width, this.onTap});
  final SeerrTitle title;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = SizedBox(
      width: width,
      height: width * 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SoupRadii.card),
        child: TmdbImage(
          path: title.posterPath,
          kind: TmdbImageKind.poster,
          fallbackTitle: title.title,
          fallbackFontSize: 14,
          cacheWidth: (width * 2).round(),
        ),
      ),
    );
    if (onTap == null) return tile;
    return Semantics(
      button: true,
      label: title.title,
      child: GestureDetector(onTap: onTap, child: tile),
    );
  }
}

/// The idle copy: what the wall is, and the way in.
class _Copy extends StatelessWidget {
  const _Copy({
    required this.touch,
    required this.wide,
    required this.focusNode,
    required this.onSurprise,
  });

  final bool touch;
  final bool wide;
  final FocusNode focusNode;
  final VoidCallback onSurprise;

  @override
  Widget build(BuildContext context) {
    final gutter = touch ? 16.0 : SoupSpacing.gutter;
    final column = SizedBox(
      width: wide ? (touch ? 380 : 440) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'HIDDEN GEMS',
            style: SoupType.style(
              size: touch ? 13 : 14,
              weight: 800,
              letterSpacing: 1,
              color: SoupColors.accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Loved by few',
            style: SoupType.style(
              size: touch ? (wide ? 44 : 36) : 54,
              weight: 800,
              letterSpacing: touch ? -1.5 : -2,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Highly rated films most people haven't found yet.",
            style: SoupType.style(
              size: touch ? 16 : 18,
              color: SoupColors.ink2,
              height: 1.45,
            ),
          ),
          SizedBox(height: touch ? 14 : 20),
          _Pill(
            focusNode: focusNode,
            touch: touch,
            label: 'Surprise me',
            icon: Icons.shuffle_rounded,
            tone: _PillTone.ink,
            onPressed: onSurprise,
          ),
        ],
      ),
    );
    return wide
        ? Positioned(
            left: gutter,
            top: 0,
            bottom: 0,
            child: Center(child: column),
          )
        : Positioned(left: gutter, right: gutter, bottom: 32, child: column);
  }
}

enum _PillTone { accent, ink, glass, quiet }

/// Rounded-full action, as on the web's Explore (the app's SoupButton is the
/// squarer item-page style).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.tone,
    required this.touch,
    this.icon,
    this.onPressed,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final _PillTone tone;
  final bool touch;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final height = touch ? 46.0 : 52.0;
    return Focusable(
      focusNode: focusNode,
      radius: height / 2,
      onActivate: onPressed,
      builder: (context, focused) {
        final (fill, ink) = switch (tone) {
          _PillTone.accent => (SoupColors.accent, SoupColors.canvas),
          _PillTone.ink => (SoupColors.ink, SoupColors.canvas),
          _PillTone.glass => (
            focused ? SoupColors.glassFocused : SoupColors.glass,
            SoupColors.ink,
          ),
          _PillTone.quiet => (
            focused ? SoupColors.glassFocused : SoupColors.faint,
            SoupColors.ink,
          ),
        };
        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: touch ? 20 : 26),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(height / 2),
            border: tone == _PillTone.glass
                ? Border.all(color: SoupColors.faint)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: touch ? 20 : 22, color: ink),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: SoupType.style(
                  size: touch ? 15 : 17,
                  weight: 800,
                  color: ink,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Back to the wall',
    child: Focusable(
      radius: 20,
      onActivate: onPressed,
      builder: (context, focused) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: focused ? SoupColors.glassFocused : SoupColors.glass,
          shape: BoxShape.circle,
          border: Border.all(color: SoupColors.faint),
        ),
        child: const Icon(Icons.close_rounded, size: 20),
      ),
    ),
  );
}

/// "[Back] back to the wall", with the remote's key drawn as a keycap.
class _BackHint extends StatelessWidget {
  const _BackHint();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0x24FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              offset: Offset(0, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.undo_rounded, size: 14, color: SoupColors.ink),
            const SizedBox(width: 4),
            Text('Back', style: SoupType.style(size: 12, weight: 800)),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'back to the wall',
        style: SoupType.style(size: 14, weight: 600, color: SoupColors.muted),
      ),
    ],
  );
}

/// Plays the reveal on mount: the poster swings up from the wall's tilt
/// ([lift]); the copy fades in a beat later. Re-keyed per reveal.
class _Arrive extends StatelessWidget {
  const _Arrive({
    required this.child,
    this.lift = false,
    this.delay = 0,
    super.key,
  });

  final Widget child;
  final bool lift;

  /// Fraction of the run to wait before starting.
  final double delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: lift ? 450 : 470),
      child: child,
      builder: (context, t, child) {
        final local = delay == 0
            ? t
            : ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (lift) {
          final c = Curves.easeOutBack.transform(local);
          return Opacity(
            opacity: Curves.easeOut.transform(local),
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - c)),
              child: Transform.rotate(
                angle: -8 * math.pi / 180 * (1 - c),
                child: Transform.scale(scale: 0.85 + 0.15 * c, child: child),
              ),
            ),
          );
        }
        final c = Curves.easeOut.transform(local);
        return Opacity(
          opacity: c,
          child: Transform.translate(
            offset: Offset(-8 * (1 - c), 0),
            child: child,
          ),
        );
      },
    );
  }
}
