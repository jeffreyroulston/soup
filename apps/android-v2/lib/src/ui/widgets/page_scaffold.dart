import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';
import '../../navigation.dart';
import 'error_state.dart';
import 'glass_nav.dart';

/// Page shell: scrolling content under the fixed [GlassNav]. The nav turns
/// solid after a short scroll, like the web header.
class PageScaffold extends StatefulWidget {
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
  bool _navFocused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final solid = _controller.hasClients && _controller.offset > 24;
      if (solid != _solid) setState(() => _solid = solid);
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _navTarget.dispose();
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
        widget.section == NavSection.search ||
        widget.section == NavSection.settings;
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
        }
      },
      child: Scaffold(
        backgroundColor: SoupColors.canvas,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomScrollView(
                controller: _controller,
                slivers: [
                  ...widget.slivers,
                  const SliverToBoxAdapter(child: SizedBox(height: 72)),
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Moving up into the nav brings the page back to the top, so the
              // header isn't left hidden behind the bar.
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (focused) {
                  setState(() => _navFocused = focused);
                  if (focused) _scrollToTop();
                },
                child: GlassNav(
                  section: widget.section,
                  libraryId: widget.libraryId,
                  solid: _solid,
                  activeFocusNode: _navTarget,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
