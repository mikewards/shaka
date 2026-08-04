import 'package:flutter/material.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/live_wind_service.dart';

/// Upgrades a snapshot wind display to the near-real-time reading in place.
///
/// Renders [builder] immediately with the cached live reading (or null), then
/// rebuilds once the shared [LiveWindService] fetch resolves — the same
/// source the spot detail screen uses, so a list card and the detail screen
/// always show the same current-wind number.
class LiveWindValue extends StatefulWidget {
  final String spotId;
  final Widget Function(BuildContext context, LiveWind? live) builder;

  const LiveWindValue({
    super.key,
    required this.spotId,
    required this.builder,
  });

  @override
  State<LiveWindValue> createState() => _LiveWindValueState();
}

class _LiveWindValueState extends State<LiveWindValue> {
  LiveWind? _live;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LiveWindValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spotId != widget.spotId) {
      _live = null;
      _load();
    }
  }

  void _load() {
    _live = LiveWindService.instance.peek(widget.spotId);
    if (_live != null) return;
    LiveWindService.instance.get(widget.spotId).then((wind) {
      if (mounted && wind != null) setState(() => _live = wind);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _live);
}
