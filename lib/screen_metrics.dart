import 'dart:math' as math;
import 'dart:ui';

import 'constants.dart';

/// Physical display corner radius in points, keyed by the screen's size in
/// points — which is what identifies an Apple Watch model at runtime, since
/// watchOS exposes no API for the corner itself.
///
/// The numbers are measured off the framebuffer masks Xcode ships with each
/// simulator device type — the `framebufferMask` PDF inside
/// `<device>.simdevicetype/Contents/Resources/` — which is the same silhouette
/// the hardware clips to. A circle fits each mask's corner to within ~1pt.
///
/// It has to be a table rather than a formula: the radius is *not* a fixed
/// fraction of the screen. It runs from 0.18x the width on a 40mm SE to 0.28x
/// on a 49mm Ultra 3, so a single ratio is wrong at both ends of the lineup —
/// which is exactly how a border tuned on one watch ends up sliced off by the
/// bezel on another.
const Map<(int, int), double> _kDisplayCornerRadius = <(int, int), double>{
  (162, 197): 29.1, // 40mm — Series 4-6, SE, SE 2, SE 3
  (176, 215): 38.9, // 41mm — Series 7-9
  (184, 224): 35.2, // 44mm — Series 4-6, SE, SE 2, SE 3
  (187, 223): 46.2, // 42mm — Series 10, 11
  (198, 242): 42.0, // 45mm — Series 7-9
  (205, 251): 56.5, // 49mm — Ultra, Ultra 2
  (208, 248): 52.3, // 46mm — Series 10, 11
  (211, 257): 59.4, // 49mm — Series 11 Ultra 3
};

/// Middle of the measured range, used for a watch this build has never heard
/// of. Erring high is the safe direction: an over-rounded playfield loses a
/// little area, an under-rounded one loses its corners to the bezel.
const double _kUnknownWatchCornerRatio = 0.26;

/// The screen resolved into the fixed logical stage the game is authored in.
///
/// Crown Breaker is tuned in absolute numbers — a 45pt paddle, 8pt bricks,
/// 7.5pt HUD type. Drawn straight onto the panel those mean different things on
/// every watch: a 42mm is 223pt tall and a 49mm Ultra 3 is 257pt, so the same
/// paddle covers 11% of one screen and 9.6% of the other, and the same brick
/// grid leaves a different amount of room to react in. The game plays
/// measurably differently per model, which is the bug.
///
/// So the simulation runs in a viewport of fixed height ([kStageHeight]) and
/// the whole scene is scaled to the panel, exactly as the tvOS path already
/// does with [kTvLogicalHeight]. Width follows the panel's own aspect ratio, so
/// the scale is uniform and nothing is stretched. Across the whole watch
/// lineup the stage then comes out 183-188pt wide — a 2.5% spread, against the
/// 27% spread of the raw panels.
///
/// [cornerRadius] is the one thing that cannot be normalised away, because it
/// is a property of the glass rather than of the resolution. It is carried
/// through into stage units so the rest of the game never has to think in
/// device points.
class ScreenMetrics {
  const ScreenMetrics._({
    required this.stage,
    required this.scale,
    required this.cornerRadius,
    required this.borderRadius,
  });

  /// Resolve the metrics for a panel of [panel] logical points.
  factory ScreenMetrics.forPanel(Size panel, {required bool isTv}) {
    final double stageHeight = isTv ? kTvLogicalHeight : kStageHeight;
    final double scale = panel.height <= 0 ? 1.0 : panel.height / stageHeight;
    final Size stage = Size(panel.width / scale, stageHeight);

    // A TV panel is a rectangle: nothing is cut away, so there is no curve for
    // anything to keep clear of and no outer corner to sit concentric inside.
    // Its border radius is a plain design choice, which is what it always was.
    if (isTv) {
      return ScreenMetrics._(
        stage: stage,
        scale: scale,
        cornerRadius: 0,
        borderRadius: kGameCornerRadius,
      );
    }

    final double corner = _watchCornerRadius(panel) / scale;
    return ScreenMetrics._(
      stage: stage,
      scale: scale,
      cornerRadius: corner,
      borderRadius: math.max(0, corner - kGameMargin),
    );
  }

  /// Stand-in until the first layout pass reports a real size.
  static const ScreenMetrics unknown = ScreenMetrics._(
    stage: Size(184, kStageHeight),
    scale: 1.0,
    cornerRadius: 35.2,
    borderRadius: 35.2 - kGameMargin,
  );

  static double _watchCornerRadius(Size panel) {
    final (int, int) key = (panel.width.round(), panel.height.round());
    return _kDisplayCornerRadius[key] ??
        panel.shortestSide * _kUnknownWatchCornerRatio;
  }

  /// The logical viewport the game simulates and draws in.
  final Size stage;

  /// Stage units per device point. 1.0 on a 44mm, ~1.15 on a 49mm Ultra 3.
  final double scale;

  /// How much of the screen's corner is cut away by the glass, in stage units.
  /// Zero on a TV, where the panel is a plain rectangle.
  final double cornerRadius;

  /// Corner radius of the playfield border, in stage units.
  ///
  /// On a watch this is [cornerRadius] less [kGameMargin], which makes the
  /// border *concentric* with the display's own corner and so a constant
  /// distance from the bezel the whole way round. A fixed radius cannot do
  /// that — on an Ultra 3 a 32pt corner inset 6pt bulges ~3pt outside the
  /// display mask along the diagonal, so the border's four corners are simply
  /// not on the screen.
  final double borderRadius;

  /// The playfield border.
  RRect get playfield => RRect.fromRectAndRadius(
    Rect.fromLTWH(
      kGameMargin,
      kGameMargin,
      stage.width - 2 * kGameMargin,
      stage.height - 2 * kGameMargin,
    ),
    Radius.circular(borderRadius),
  );

  /// How far in from the left or right edge the glass has been cut away, at
  /// [fromEdge] stage units below the top edge (or above the bottom one).
  ///
  /// This is what anything pinned near a corner has to clear. A HUD row at
  /// y=14 needs 7pt of side inset on a 44mm and 16pt on an Ultra 3; pinning it
  /// at one fixed number is why the pause button falls off the biggest watch.
  double cornerInsetAt(double fromEdge) {
    if (fromEdge >= cornerRadius || fromEdge <= 0) return 0;
    final double dy = cornerRadius - fromEdge;
    return cornerRadius - math.sqrt(cornerRadius * cornerRadius - dy * dy);
  }

  /// [cornerInsetAt], floored at [atLeast] and given [clearance] of breathing
  /// room — the form every caller actually wants.
  double sideInsetFor(
    double fromEdge, {
    double atLeast = 0,
    double clearance = 0,
  }) {
    final double corner = cornerInsetAt(fromEdge);
    return math.max(atLeast, corner == 0 ? 0 : corner + clearance);
  }
}
