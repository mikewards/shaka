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
