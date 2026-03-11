import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/spot_models.dart';

/// Expandable card for detailed swell & exposure data.
///
/// COLLAPSED: Shows the swell-at-spot value (e.g., "3.2ft @ 14s SW").
/// EXPANDED: Shows all available swell readings and exposure info.
class SwellDetailsCard extends StatefulWidget {
  final SpotConditions conditions;

  const SwellDetailsCard({super.key, required this.conditions});

  @override
  State<SwellDetailsCard> createState() => _SwellDetailsCardState();
}

class _SwellDetailsCardState extends State<SwellDetailsCard> {
  bool _expanded = false;

  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildHeader(),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildExpandedContent(),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final swellValue =
        widget.conditions.swellCorrected ?? widget.conditions.swell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _expanded = !_expanded);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                swellValue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    final c = widget.conditions;
    final items = <(String, String)>[];

    if (c.swellCorrected != null) {
      items.add(('Swell (at spot)', c.swellCorrected!));
      if (c.swellCorrected != c.swell) {
        items.add(('Swell (open ocean)', c.swell));
      }
    } else {
      items.add(('Swell', c.swell));
    }

    if (c.secondarySwell != null) {
      if (c.secondarySwellCorrected != null) {
        items.add(('2nd Swell (at spot)', c.secondarySwellCorrected!));
        if (c.secondarySwellCorrected != c.secondarySwell) {
          items.add(('2nd Swell (open ocean)', c.secondarySwell!));
        }
      } else {
        items.add(('2nd Swell', c.secondarySwell!));
      }
    }

    if (c.exposureBearing != null) {
      items.add((
        'Exposure',
        'Faces ${_bearingToCardinal(c.exposureBearing!)} (${c.exposureWidth ?? 0}°)',
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.white10),
          for (int i = 0; i < items.length; i++)
            _buildRow(
              items[i].$1,
              items[i].$2,
              isLast: i == items.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isLast = false}) {
    return Container(
      padding: EdgeInsets.only(top: 10, bottom: isLast ? 4 : 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static String _bearingToCardinal(int degrees) {
    const dirs = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    return dirs[((degrees % 360) / 22.5).round() % 16];
  }
}
