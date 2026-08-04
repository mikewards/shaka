import 'package:flutter/material.dart';
import '../../core/utils/wind_format.dart';

/// Tiny one-line caption for the wind layer on ocean map surfaces: the
/// raster is a coarse offshore model, so sheltered/lee spots can read
/// differently than the spot forecast. Deliberately terse and
/// non-interactive so it never competes with the map.
class OceanMapWindHint extends StatelessWidget {
  const OceanMapWindHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 11, color: Colors.white54),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                WindFormat.mapWindHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
