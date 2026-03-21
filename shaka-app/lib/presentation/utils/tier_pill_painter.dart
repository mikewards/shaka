import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Tier-to-color mapping shared across all map screens.
const tierDefs = <int, Color>{
  5: AppColors.scoreExcellent,
  4: AppColors.scoreGood,
  3: AppColors.scoreAverage,
  2: AppColors.scoreBelowAvg,
  1: AppColors.scorePoor,
  0: Color(0xFF555555),
};

/// Tier-to-label mapping for chip text.
const tierLabels = <int, String>{
  5: 'Excellent',
  4: 'Good',
  3: 'Average',
  2: 'Below Avg',
  1: 'Poor',
  0: '—',
};

/// Map a shaka score to its chip icon key (e.g. "chip-3").
String chipKeyForScore(int? score) {
  if (score == null) return 'chip-0';
  return 'chip-${AppColors.getScoreTier(score)}';
}

/// Paint a colored circle with the tier label text centered inside.
///
/// All circles are the same diameter regardless of label length.
/// Returns PNG bytes suitable for MapLibre `addImage`.
Future<Uint8List> generateScoreChipImage(
  int tier,
  Color tierColor,
  String label,
) async {
  const double px = 4.0;
  const double fontSize = 3.2 * px;
  const double diameter = 18.0 * px; // fixed size for all tiers
  const double shadowSpace = 2.0 * px;
  const double totalSize = diameter + shadowSpace * 2;

  final textStyle = ui.TextStyle(
    color: Colors.white,
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  final pb = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: TextAlign.center),
  )
    ..pushStyle(textStyle)
    ..addText(label);
  final paragraph = pb.build()
    ..layout(const ui.ParagraphConstraints(width: 400));

  final textW = paragraph.longestLine.ceilToDouble();
  final textH = paragraph.height;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, totalSize, totalSize),
  );

  final center = Offset(totalSize / 2, totalSize / 2);
  const radius = diameter / 2;

  // Drop shadow
  canvas.drawCircle(
    center + Offset(0, 1.5 * px),
    radius,
    Paint()
      ..color = Colors.black.withOpacity(0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
  );

  // Circle fill
  canvas.drawCircle(center, radius, Paint()..color = tierColor);

  // Text centered
  final textX = (totalSize - textW) / 2;
  final textY = (totalSize - textH) / 2;
  canvas.drawParagraph(paragraph, Offset(textX, textY));

  final size = totalSize.ceil();
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Map a shaka score to its selected-chip icon key.
String selectedChipKeyForScore(int? score) {
  if (score == null) return 'selected-chip-0';
  return 'selected-chip-${AppColors.getScoreTier(score)}';
}

/// Build a geometric shaka hand (hang-loose) silhouette path.
///
/// Composed of three rounded rectangles unioned together:
/// a central palm/fist, a thumb extending upper-right, and a
/// pinky extending lower-right. Bold and readable at 24-30 dp.
Path _buildShakaPath(double size) {
  final s = size / 100.0;

  // Central palm / fist body
  final palmPath = Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(20 * s, 28 * s, 38 * s, 40 * s),
      Radius.circular(12 * s),
    ));

  // Thumb: rounded rect rotated ~-25° extending from upper-right of palm
  final thumbRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset.zero,
      width: 16 * s,
      height: 40 * s,
    ),
    Radius.circular(8 * s),
  );
  final thumbPath = Path()..addRRect(thumbRect);
  final thumbXform = Float64List(16);
  Matrix4.identity()
    ..translate(55 * s, 18 * s)
    ..rotateZ(-25 * math.pi / 180)
    ..copyIntoArray(thumbXform);
  final transformedThumb = thumbPath.transform(thumbXform);

  // Pinky: rounded rect rotated ~25° extending from lower-right of palm
  final pinkyRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset.zero,
      width: 14 * s,
      height: 36 * s,
    ),
    Radius.circular(7 * s),
  );
  final pinkyPath = Path()..addRRect(pinkyRect);
  final pinkyXform = Float64List(16);
  Matrix4.identity()
    ..translate(53 * s, 78 * s)
    ..rotateZ(25 * math.pi / 180)
    ..copyIntoArray(pinkyXform);
  final transformedPinky = pinkyPath.transform(pinkyXform);

  // Union all three shapes into one silhouette
  var combined = Path.combine(PathOperation.union, palmPath, transformedThumb);
  combined = Path.combine(PathOperation.union, combined, transformedPinky);
  return combined;
}

/// Generate a shaka-hand silhouette marker filled with [tierColor].
///
/// Used for the *selected* spot on the explore map — visually distinct
/// from the standard score-chip circles.
Future<Uint8List> generateSelectedShakaImage(
  int tier,
  Color tierColor,
) async {
  const double px = 4.0;
  const double iconSize = 26.0 * px;
  const double pad = 6.0 * px;
  const double totalSize = iconSize + pad * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, totalSize, totalSize),
  );

  canvas.translate(pad, pad);
  final path = _buildShakaPath(iconSize);

  // Layer 1 — drop shadow
  canvas.save();
  canvas.translate(0, 2 * px);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
  );
  canvas.restore();

  // Layer 2 — white outline for contrast on any map tile
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * px
      ..strokeJoin = StrokeJoin.round,
  );

  // Layer 3 — solid tier-color fill
  canvas.drawPath(path, Paint()..color = tierColor);

  final size = totalSize.ceil();
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
