import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme/app_colors.dart';

ui.Image? _shakaSourceImage;

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
  const double diameter = 18.0 * px;
  const double totalSize = diameter;

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

Future<ui.Image> _loadShakaSource() async {
  if (_shakaSourceImage != null) return _shakaSourceImage!;
  final data = await rootBundle.load('assets/shaka_silhouette.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  _shakaSourceImage = frame.image;
  return _shakaSourceImage!;
}

/// Generate a shaka-hand marker filled with [tierColor] from the PNG asset.
///
/// Used for the *selected* spot on the explore map — visually distinct
/// from the standard score-chip circles.
Future<Uint8List> generateSelectedShakaImage(
  int tier,
  Color tierColor,
) async {
  final src = await _loadShakaSource();
  const double px = 4.0;
  const double iconW = 30.0 * px;
  final double aspect = src.height / src.width;
  final double iconH = iconW * aspect;
  const double pad = 6.0 * px;
  final double totalW = iconW + pad * 2;
  final double totalH = iconH + pad * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, totalW, totalH),
  );

  final dst = Rect.fromLTWH(pad, pad, iconW, iconH);
  final srcRect = Rect.fromLTWH(
    0, 0, src.width.toDouble(), src.height.toDouble(),
  );

  // White outline — uniform scale from center so border is even on all sides
  const outlineScale = 1.06;
  final whiteDst = Rect.fromCenter(
    center: dst.center,
    width: dst.width * outlineScale,
    height: dst.height * outlineScale,
  );
  canvas.drawImageRect(
    src,
    srcRect,
    whiteDst,
    Paint()..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn),
  );

  // Tier-color fill
  canvas.drawImageRect(
    src,
    srcRect,
    dst,
    Paint()..colorFilter = ColorFilter.mode(tierColor, BlendMode.srcIn),
  );

  final image = await recorder.endRecording().toImage(totalW.ceil(), totalH.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
