import 'package:flutter/material.dart';

import '../../form_factor.dart';
import '../theme/soup_tokens.dart';
import '../../navigation.dart';
import 'error_state.dart';
import 'glass_nav.dart';

/// Page shell: scrolling content under the fixed [GlassNav]. The nav turns
/// solid after a short scroll, like the web header.
///
/// Every page draws its own bar, but in the same place with the same
/// (cached) tabs, and page transitions fade only the content beneath it, so
/// the bar reads as one header that stays put across pages.
class PageScaffold extends StatefulWidget {
  /// Set while a nav-bar item opens a page; that page then focuses its own
  /// nav item, so focus stays in the bar instead of jumping to the content.
  static bool _holdNav = false;

  /// Called by the nav bar before it opens a top-level page.
  static void holdNavFocus() {
    _holdNav = true;
    // Spent by the page built on the next frame, or dropped if none is.
    WidgetsBinding.instance.addPostFrameCallback((_) => _holdNav = false);
  }

  /// D-pad focus recovery (see DesignScale): focuses the current page's nav
  /// item, or the nav's first item on pages without a section. False when no
  /// page is showing (e.g. the player).
  static bool focusNav() {
    for (final page in _PageScaffoldState._pages) {
      if (!page.mounted || page.context.isTouch) continue;
      if (ModalRoute.of(page.context)?.isCurrent != true) continue;
      final target = page._navTarget.context != null
          ? page._navTarget
          : page._navArea.traversalDescendants
                .where((n) => n.canRequestFocus)
                .firstOrNull;
      if (target == null) return false;
      // Focusing the nav also scrolls the page back to the top.
      target.requestFocus();
      return true;
    }
    return false;
  }

  /// Nothing usable has focus: none at all, a scope with no item, an item
  /// whose widget is gone, or one left wholly off-screen. An item is not lost
  /// while a list it sits in is still scrolling: holding an arrow moves focus
  /// faster than the reveal scroll, so it briefly runs past the screen edge.
  static bool focusLost(FocusNode? node) {
    if (node == null || node is FocusScopeNode) return true;
    final context = node.context;
    if (context == null || !context.mounted || !node.canRequestFocus) {
      return true;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return true;
    final screen = node.nearestScope?.rect;
    if (screen == null || node.rect.overlaps(screen)) return false;
    return !_scrolling(context);
  }

  static bool _scrolling(BuildContext context) {
    for (
      var s = Scrollable.maybeOf(context);
      s != null;
      s = Scrollable.maybeOf(s.context)
    ) {
      if (s.position.isScrollingNotifier.value) return true;
    }
    return false;
  }

  const PageScaffold({
    required this.section,
    required this.slivers,
    this.libraryId,
    this.controller,
    this.overlay,
    super.key,
  });

  final NavSection section;
  final String? libraryId;
  final List<Widget> slivers;
  final ScrollController? controller;

  /// Pinned above the content, under the nav (e.g. the library A–Z strip).
  final Widget? overlay;

  @override
  State<PageScaffold> createState() => _PageScaffoldState();
}

class _PageScaffoldState extends State<PageScaffold> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool _solid = false;

  /// The nav item for this page's section; Back focuses it.
  final _navTarget = FocusNode(debugLabel: 'nav target');

  /// Wraps the whole nav bar; its first item is the fallback when this page
  /// has no section of its own (detail pages).
  final _navArea = FocusNode(
    debugLabel: 'nav area',
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _navFocused = false;

  static final _pages = <_PageScaffoldState>{};

  @override
  void initState() {
    super.initState();
    _pages.add(this);
    if (PageScaffold._holdNav && widget.section != NavSection.none) {
      PageScaffold._holdNav = false;
      // Not attached yet: the request applies as the nav item mounts, ahead
      // of the content's autofocus (which only fills an empty scope).
      _navTarget.requestFocus();
    }
    _controller.addListener(() {
      final solid = _controller.hasClients && _controller.offset > 24;
      if (solid != _solid) setState(() => _solid = solid);
    });
  }

  @override
  void dispose() {
    _pages.remove(this);
    if (widget.controller == null) _controller.dispose();
    _navTarget.dispose();
    _navArea.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.section == NavSection.home;
    final tab =
        widget.section == NavSection.library ||
        widget.section == NavSection.myStuff ||
        widget.section == NavSection.search ||
        widget.section == NavSection.settings;
    final route = ModalRoute.of(context);
    final animation = route?.animation ?? kAlwaysCompleteAnimation;
    final covering = route?.secondaryAnimation ?? kAlwaysDismissedAnimation;
    return PopScope(
      // tvOS-style Back on top-level pages: first press returns to the top
      // and focuses this page's nav item; from the nav, a tab goes Home and
      // Home leaves the app. Detail pages (section none) just pop.
      canPop: !tab && (!home || _navFocused),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !(home || tab)) return;
        if (!_navFocused && _navTarget.context != null) {
          _navTarget.requestFocus();
          _scrollToTop();
        } else if (tab) {
          openHome(context);
          PageScaffold.focusNav();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: FadeTransition(
                opacity: animation,
                child: ColoredBox(
                  color: SoupColors.canvas,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomScrollView(
                          controller: _controller,
                          slivers: [
                            ...widget.slivers,
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 72),
                            ),
                          ],
                        ),
                      ),
                      ?widget.overlay,
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 28,
                        child: Center(child: ConnectionBanner()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Moving up into the nav brings the page back to the top, so the
              // header isn't left hidden behind the bar.
              child: Focus(
                focusNode: _navArea,
                onFocusChange: (focused) {
                  setState(() => _navFocused = focused);
                  if (focused) _scrollToTop();
                },
                child: _NavFade(
                  animation: animation,
                  covering: covering,
                  child: GlassNav(
                    section: widget.section,
                    libraryId: widget.libraryId,
                    solid: _solid,
                    activeFocusNode: _navTarget,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar on screen at a time: a page's bar shows at once when it opens and
/// hides while another page covers it; when a page closes, its bar fades out
/// over the one returning beneath it.
class _NavFade extends StatelessWidget {
  const _NavFade({
    required this.animation,
    required this.covering,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> covering;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([animation, covering]),
    child: child,
    builder: (context, child) {
      final covered =
          covering.status == AnimationStatus.forward ||
          covering.status == AnimationStatus.completed;
      final closing = animation.status == AnimationStatus.reverse;
      return Opacity(
        opacity: covered ? 0 : (closing ? animation.value : 1),
        child: child,
      );
    },
  );
}
