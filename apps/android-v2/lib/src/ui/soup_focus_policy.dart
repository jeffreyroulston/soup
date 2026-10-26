import 'package:flutter/widgets.dart';

/// D-pad traversal modelled on Android's `FocusFinder`, replacing Flutter's
/// default directional search (which happily jumps diagonally or backwards).
///
/// * Only targets that lie strictly in the pressed direction are considered.
/// * Targets overlapping the current item's "beam" (its row for left/right,
///   its column for up/down) win over ones outside it.
/// * Reversing a move returns to where you came from, so Down, Down, Up, Up
///   retraces the same path rather than taking geometric neighbours.
/// * Left/right stays within the current row; at its end focus stays put.
/// * Off-screen items are only reachable through the list they scroll in.
class SoupFocusPolicy extends ReadingOrderTraversalPolicy {
  SoupFocusPolicy();

  // Shared by every group so "came from" survives crossing group boundaries.
  static final _history =
      <({FocusNode from, FocusNode to, TraversalDirection direction})>[];

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);
    final from = currentNode.rect;
    final scrollables = _scrollablesOf(currentNode.context);
    final candidates = [
      for (final node in scope.traversalDescendants)
        if (!identical(node, currentNode) &&
            node.canRequestFocus &&
            node.context != null &&
            // Leaves only: a wrapper Focus around a field is not a target.
            !node.traversalDescendants.any((d) => d.canRequestFocus) &&
            _isInDirection(from, node.rect, direction) &&
            _reachable(node, scope.rect, scrollables))
          node,
    ];

    final last = _history.lastOrNull;
    if (last != null &&
        identical(last.to, currentNode) &&
        _opposite(last.direction) == direction &&
        candidates.contains(last.from)) {
      _history.removeLast();
      last.from.requestFocus();
      return true;
    }
    final target = _best(from, candidates, direction);
    if (target == null) return false;
    // A fresh move from anywhere but the end of the path starts a new path.
    if (last != null && !identical(last.to, currentNode)) _history.clear();
    _history.add((from: currentNode, to: target, direction: direction));
    if (_history.length > 16) _history.removeAt(0);
    target.requestFocus();
    return true;
  }

  static Set<ScrollableState> _scrollablesOf(BuildContext? context) {
    final found = <ScrollableState>{};
    var scrollable = context == null ? null : Scrollable.maybeOf(context);
    while (scrollable != null && found.add(scrollable)) {
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return found;
  }

  /// Off-screen items are only reachable by scrolling a list they share
  /// with the current item, along the axis they're off-screen on. Fixed
  /// chrome (the top nav) must not dive into content scrolled up behind it,
  /// and Right must not reach a card off the edge of another row (both rows
  /// share the page's vertical scroll, but only the row's own list scrolls
  /// sideways).
  static bool _reachable(
    FocusNode node,
    Rect screen,
    Set<ScrollableState> currentScrollables,
  ) {
    final c = node.rect.center;
    final offX = c.dx < screen.left || c.dx > screen.right;
    final offY = c.dy < screen.top || c.dy > screen.bottom;
    if (!offX && !offY) return true;
    final shared = _scrollablesOf(
      node.context,
    ).where(currentScrollables.contains).map((s) => s.position.axis);
    return (!offX || shared.contains(Axis.horizontal)) &&
        (!offY || shared.contains(Axis.vertical));
  }

  static bool _vertical(TraversalDirection d) =>
      d == TraversalDirection.up || d == TraversalDirection.down;

  static TraversalDirection _opposite(TraversalDirection d) => switch (d) {
    TraversalDirection.up => TraversalDirection.down,
    TraversalDirection.down => TraversalDirection.up,
    TraversalDirection.left => TraversalDirection.right,
    TraversalDirection.right => TraversalDirection.left,
  };

  /// [to] sits beyond [from] in [d]: its centre is past ours and its far
  /// edge extends further (so overlapping or enclosing boxes don't count).
  static bool _isInDirection(Rect from, Rect to, TraversalDirection d) =>
      switch (d) {
        TraversalDirection.down =>
          to.center.dy > from.center.dy + 1 && to.bottom > from.bottom,
        TraversalDirection.up =>
          to.center.dy < from.center.dy - 1 && to.top < from.top,
        TraversalDirection.right =>
          to.center.dx > from.center.dx + 1 && to.right > from.right,
        TraversalDirection.left =>
          to.center.dx < from.center.dx - 1 && to.left < from.left,
      };

  /// Overlap across the direction of travel (up/down only: same column).
  static bool _inBeam(Rect from, Rect to) =>
      to.right > from.left && to.left < from.right;

  /// 0: in our row/column. 1 (left/right only): centred within half our
  /// height of the row, so slightly offset controls (hero buttons + carousel
  /// arrows) still read as one row. 2 (up/down only): anywhere below/above.
  /// Left/right never leaves the row, so returns null past tier 1.
  ///
  /// Tier 0 for left/right needs the candidate's centre inside our band too:
  /// a tall card's band otherwise overlaps the bottom of the row above.
  static int? _tier(Rect from, Rect to, TraversalDirection d) {
    if (_vertical(d)) return _inBeam(from, to) ? 0 : 2;
    final y = to.center.dy;
    if (y >= from.top && y <= from.bottom) return 0;
    final slack = from.height / 2;
    return y >= from.top - slack && y <= from.bottom + slack ? 1 : null;
  }

  /// Gap between the facing edges along the direction of travel.
  static double _major(Rect from, Rect to, TraversalDirection d) => switch (d) {
    TraversalDirection.down => to.top - from.bottom,
    TraversalDirection.up => from.top - to.bottom,
    TraversalDirection.right => to.left - from.right,
    TraversalDirection.left => from.left - to.right,
  }.clamp(0.0, double.infinity);

  /// Offset across the direction of travel, measured from our leading edge
  /// (left for vertical moves, top for horizontal) so rows of mixed widths
  /// line up the way the eye expects.
  static double _minor(Rect from, Rect to, TraversalDirection d) => _vertical(d)
      ? (to.left - from.left).abs()
      : (to.center.dy - from.center.dy).abs();

  /// Distance to the candidate's far edge along the direction of travel.
  static double _majorFar(Rect from, Rect to, TraversalDirection d) =>
      switch (d) {
        TraversalDirection.down => to.bottom - from.bottom,
        TraversalDirection.up => from.top - to.top,
        TraversalDirection.right => to.right - from.right,
        TraversalDirection.left => from.left - to.left,
      };

  /// Gap between the rects across the direction of travel (0 if overlapping).
  static double _crossGap(Rect from, Rect to, TraversalDirection d) =>
      (_vertical(d)
              ? (to.left > from.right
                    ? to.left - from.right
                    : from.left - to.right)
              : (to.top > from.bottom
                    ? to.top - from.bottom
                    : from.top - to.bottom))
          .clamp(0.0, double.infinity);

  static FocusNode? _best(
    Rect from,
    List<FocusNode> candidates,
    TraversalDirection d,
  ) {
    FocusNode? beam;
    var beamScore = double.infinity;
    final outside = <FocusNode>[];
    for (final node in candidates) {
      final to = node.rect;
      final tier = _tier(from, to, d);
      if (tier == null) continue;
      if (tier == 2) {
        outside.add(node);
        continue;
      }
      // Tier 0 beats tier 1; then the nearest, then the best aligned.
      final score =
          tier * 1e9 + _major(from, to, d) * 1000 + _minor(from, to, d);
      if (score < beamScore) {
        beamScore = score;
        beam = node;
      }
    }
    // Like Android: an in-beam target wins unless something just outside the
    // beam lies wholly before it and nearer sideways than the beam target is
    // ahead (a lone pill between a button row and a shelf, not a far-off
    // carousel arrow).
    final beamMajor = beam == null
        ? double.infinity
        : _major(from, beam.rect, d);
    FocusNode? best;
    var bestScore = double.infinity;
    for (final node in outside) {
      final to = node.rect;
      if (_majorFar(from, to, d) > beamMajor ||
          _crossGap(from, to, d) > beamMajor) {
        continue;
      }
      final major = _major(from, to, d);
      final minor = _minor(from, to, d);
      final score = 13 * major * major + minor * minor;
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    return best ?? beam;
  }
}
