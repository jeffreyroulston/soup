import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../theme/soup_tokens.dart';
import '../widgets/catalog_builder.dart';
import '../widgets/glass_nav.dart' show NavSection;
import '../widgets/soup_wordmark.dart';
import '../widgets/error_state.dart';

/// Touch page shell: a scrolling page with a frosted top bar and, on the
/// top-level sections, a bottom navigation bar (Home, Library, Search,
/// Settings). Detail pages ([NavSection.none]) get a back button instead and
/// can let their artwork run under the status bar with [overlayTopBar].
class TouchScaffold extends StatefulWidget {
  const TouchScaffold({
    required this.section,
    required this.slivers,
    this.title,
    this.controller,
    this.overlayTopBar = false,
    this.actions = const [],
    super.key,
  });

  final NavSection section;
  final List<Widget> slivers;

  /// Shown in the top bar; the "soup" wordmark on Home when null.
  final String? title;
  final ScrollController? controller;

  /// Transparent top bar over the first sliver until the page scrolls.
  final bool overlayTopBar;
  final List<Widget> actions;

  @override
  State<TouchScaffold> createState() => _TouchScaffoldState();
}

class _TouchScaffoldState extends State<TouchScaffold> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool _solid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scrolled);
  }

  void _scrolled() {
    final solid = _controller.hasClients && _controller.offset > 24;
    if (solid != _solid) setState(() => _solid = solid);
  }

  @override
  void dispose() {
    _controller.removeListener(_scrolled);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  bool get _topLevel => widget.section != NavSection.none;

  @override
  Widget build(BuildContext context) {
    final tab =
        widget.section == NavSection.library ||
        widget.section == NavSection.myStuff ||
        widget.section == NavSection.search ||
        widget.section == NavSection.settings;
    final padding = MediaQuery.paddingOf(context);
    final barHeight = padding.top + kToolbarHeight;
    final overlay = widget.overlayTopBar;
    return PopScope(
      // Back from a tab returns Home; Home and detail pages pop as usual.
      canPop: !tab,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && tab) openHome(context);
      },
      child: Scaffold(
        backgroundColor: SoupColors.canvas,
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomScrollView(
                controller: _controller,
                slivers: [
                  if (!overlay)
                    SliverToBoxAdapter(child: SizedBox(height: barHeight)),
                  ...widget.slivers,
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 32 + padding.bottom + (_topLevel ? 64 : 0),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              // Above the bottom nav (64) on top-level pages.
              bottom: padding.bottom + (_topLevel ? 76 : 16),
              child: const Center(child: ConnectionBanner()),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                height: barHeight,
                solid: _solid || !overlay,
                title: widget.title,
                showBack: !_topLevel && Navigator.of(context).canPop(),
                actions: widget.actions,
              ),
            ),
          ],
        ),
        bottomNavigationBar: _topLevel
            ? _BottomNav(section: widget.section)
            : null,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.height,
    required this.solid,
    required this.title,
    required this.showBack,
    required this.actions,
  });

  final double height;
  final bool solid;
  final String? title;
  final bool showBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
          // Opaque canvas fades in once the page scrolls under the bar.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: solid ? 1 : 0,
            child: const ColoredBox(color: SoupColors.canvas),
          ),
          Padding(
            padding: EdgeInsets.only(top: top, left: 4, right: 8),
            child: Row(
              children: [
                if (showBack)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: SoupColors.ink,
                    ),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: title == null || solid ? 1 : 0,
                    child: title == null
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SoupWordmark(size: 26),
                          )
                        : Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SoupType.style(size: 19, weight: 800),
                          ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.section});
  final NavSection section;

  static const _sections = [
    NavSection.home,
    NavSection.library,
    NavSection.myStuff,
    NavSection.search,
    NavSection.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.libraries(),
      builder: (context, libraries, _) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xF20A0A0B),
          border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            indicatorColor: const Color(0x26FFFFFF),
            height: 64,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => SoupType.style(
                size: 12,
                weight: states.contains(WidgetState.selected) ? 800 : 600,
                color: states.contains(WidgetState.selected)
                    ? SoupColors.ink
                    : SoupColors.muted,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? SoupColors.ink
                    : SoupColors.muted,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _sections
                .indexOf(section)
                .clamp(0, _sections.length - 1),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) {
              final target = _sections[i];
              if (target == section) return;
              switch (target) {
                case NavSection.home:
                  openHome(context);
                case NavSection.library:
                  final first = libraries?.firstOrNull;
                  if (first != null) openLibrary(context, first);
                case NavSection.myStuff:
                  openFavourites(context);
                case NavSection.search:
                  openSearch(context);
                case NavSection.settings:
                  openSettings(context);
                case NavSection.none:
                  break;
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library_rounded),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: 'My Stuff',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Account',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
