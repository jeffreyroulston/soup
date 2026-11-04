import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import 'seerr_builder.dart';
import 'seerr_unavailable.dart';

/// Loads the Seerr status once and shows [builder] only when Explore can be
/// used; otherwise the matching "not set up / can't reach / failed" state.
class ExploreGate extends StatefulWidget {
  const ExploreGate({required this.builder, required this.loading, super.key});

  final Widget Function(BuildContext context, SeerrStatus status) builder;

  /// Placeholder while the status is on its way.
  final Widget loading;

  @override
  State<ExploreGate> createState() => _ExploreGateState();
}

class _ExploreGateState extends State<ExploreGate> {
  int _attempt = 0;

  void _retry() {
    // A fresh probe; the builder below reloads because its key changed.
    Seerr.of(context).loadStatus(force: true).ignore();
    setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) => SeerrBuilder<SeerrStatus>(
    load: (s) => s.loadStatus(),
    keys: [_attempt],
    builder: (context, status, error) {
      if (status == null && error == null) return widget.loading;
      if (status == null || !status.usable) {
        return SeerrUnavailable(status: status, error: error, onRetry: _retry);
      }
      return widget.builder(context, status);
    },
  );
}
