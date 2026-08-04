import 'package:flutter/material.dart';
import '../../core/utils/wind_format.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/live_wind_service.dart';
import '../../data/services/unit_preference_service.dart';

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

/// Compact current-wind text for rows that claim to show "now" (e.g. the
/// forecast Today card): renders the shared near-real-time reading with a
/// " · Live" tag, falling back to the server's snapshot string (a forecast
/// sample) until the live fetch resolves.
class CurrentWindText extends StatelessWidget {
  final String spotId;

  /// Snapshot/forecast string shown until (or if) no live reading exists.
  final String fallback;

  final TextStyle? style;

  const CurrentWindText({
    super.key,
    required this.spotId,
    required this.fallback,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final units = UnitPreferenceService();
    return LiveWindValue(
      spotId: spotId,
      builder: (context, live) => ListenableBuilder(
        listenable: units,
        builder: (context, _) => Text(
          live != null
              ? '${WindFormat.label(live.windSpeedKts, live.windDirectionCardinal, units.system)} \u00b7 Live'
              : fallback,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
