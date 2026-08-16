import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../constants.dart';
import '../models.dart';

/// Draws [shaders/neon_pulse.frag] as a glowing ring on the playfield border,
/// behind [child].
///
/// Behind, not in front: a ring thick enough to read across a room is thick
/// enough to sit on the edge bricks and the paddle, and covering gameplay is
/// worse than being partly covered by it. Underneath, the ball and paddle
/// crossing the ring look like they are riding an energy field.
///
/// The shader is painted as a *stroke*, not a fill, so only the ring's pixels
/// are shaded — the rule that makes a full-screen-looking effect affordable on
/// the watch. If the program fails to compile, [child] renders untouched.
///
/// Two rules from the flutter-watchos shader guide are load-bearing here. The
/// [ui.FragmentProgram] is compiled once per process and cached statically;
/// compiling it in `build` would stall the first frame after every navigation.
/// And the clock is a ticker from [SingleTickerProviderStateMixin], which
/// `TickerMode`-mutes when the route is covered — a bare [Ticker] would keep
/// shading an invisible screen and eat the watch's battery.
///
/// The ticker drives a [ValueNotifier] wired to the painter's `repaint`, so a
/// frame costs a repaint and not a rebuild of the whole game subtree.
class NeonPulse extends StatefulWidget {
  const NeonPulse({
    super.key,
    required this.accent,
    required this.child,
    this.flares = const <RingFlare>[],
    this.danger = 0.0,
    this.threat = 0.0,
    this.perilAxis = const Offset(0, 1),
    this.cornerRadius = kGameCornerRadius,
    this.resolution = kWatchRingResolution,
    this.enabled = true,
  });

  /// The world's neon hue. Bends toward red as [danger] rises.
  final Color accent;

  /// Live impacts to burn onto the ring. Only the last four are used.
  final List<RingFlare> flares;

  /// 0 at full lives, 1 on the last one.
  final double danger;

  /// 0..1, how close the nearest ball is to the edge that costs a life.
  final double threat;

  /// Which edge the paddle guards — the one the ball is lost through.
  /// `(0, 1)` for the bottom, `(1, 0)` for the right in vertical mode.
  final Offset perilAxis;

  /// Corner radius of the ring, which on a watch is the display's own corner
  /// minus [kGameMargin] rather than a constant — see [ScreenMetrics.playfield].
  /// Get this wrong on an Ultra and the ring's corners are behind the bezel.
  final double cornerRadius;

  /// Fraction of the panel's own resolution to shade the ring at.
  ///
  /// See [kWatchRingResolution] and [kTvRingResolution] for why this is not one
  /// number. 1.0 draws straight onto the canvas; anything less rasterises into
  /// an offscreen and scales up.
  final double resolution;

  /// Set false to skip the shader entirely.
  final bool enabled;

  final Widget child;

  @override
  State<NeonPulse> createState() => _NeonPulseState();
}

class _NeonPulseState extends State<NeonPulse>
    with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// Seconds since this ring mounted; also the painter's repaint signal.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);

  late final Ticker _ticker = createTicker((Duration elapsed) {
    _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  });

  @override
  void initState() {
    super.initState();
    _ticker.start();
    _ensureProgram();
  }

  void _ensureProgram() {
    if (_program != null) return;
    _loading ??= ui.FragmentProgram.fromAsset('shaders/neon_pulse.frag').then(
      (ui.FragmentProgram program) => _program = program,
      // Leave _program null on failure — build() renders the child untouched.
      onError: (Object _, StackTrace _) {},
    );
    _loading!.whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentProgram? program = _program;
    if (!widget.enabled || program == null) {
      return widget.child;
    }
    return CustomPaint(
      painter: _NeonPulsePainter(
        program: program,
        seconds: _seconds,
        accent: widget.accent,
        flares: widget.flares,
        danger: widget.danger,
        threat: widget.threat,
        perilAxis: widget.perilAxis,
        cornerRadius: widget.cornerRadius,
        resolution: widget.resolution,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      child: widget.child,
    );
  }
}

class _NeonPulsePainter extends CustomPainter {
  _NeonPulsePainter({
    required this.program,
    required this.seconds,
    required this.accent,
    required this.flares,
    required this.danger,
    required this.threat,
    required this.perilAxis,
    required this.cornerRadius,
    required this.resolution,
    required this.devicePixelRatio,
  }) : super(repaint: seconds);

  final ui.FragmentProgram program;
  final ValueNotifier<double> seconds;
  final Color accent;
  final List<RingFlare> flares;
  final double danger;
  final double threat;
  final Offset perilAxis;

  /// Radius of the ring's corners, concentric with the display's own.
  final double cornerRadius;

  /// Fraction of the panel's own resolution the ring is shaded at.
  final double resolution;

  /// Physical pixels per logical pixel. Half of what decides the shaded size;
  /// see [_toDevice] for the other half.
  final double devicePixelRatio;

  /// Device pixels per logical pixel of [size] — the full resolution the ring
  /// could be shaded at.
  ///
  /// It is the product of two things rather than either alone:
  ///
  /// * the device pixel ratio — 2.0 on both a watch and an Apple TV 4K;
  /// * whatever a [FittedBox] above us scales by. Both screens now author in a
  ///   fixed logical stage: ~184x224 on a watch (a small scale either side of
  ///   1.0) and ~391x220 on a TV, blown up ~4.9x to fill the panel.
  ///
  /// A painter's canvas is in *logical* pixels, so [Canvas.getTransform] sees
  /// the FittedBox but not the device pixel ratio. Using either factor alone
  /// silently quarter-resolutions one of the two screens.
  static double _toDevice(Canvas canvas, double devicePixelRatio) {
    // [0] is the x scale of the 4x4 column-major transform. The scene is only
    // ever uniformly scaled and translated, so one axis is enough.
    final double scale = canvas.getTransform()[0].abs() * devicePixelRatio;
    return scale.isFinite && scale > 0 ? scale : devicePixelRatio;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double toDevice = _toDevice(canvas, devicePixelRatio);

    if (resolution >= 1.0) {
      // Straight onto the canvas, which rasterises at whatever the panel and
      // the FittedBox above us come to — nothing to compute.
      //
      // The scale passed here is 1.0, not [toDevice], because `uSize` has to
      // match whatever space `FlutterFragCoord()` reports in, and on the live
      // canvas that is this painter's own *logical* units — the transform above
      // is baked into the geometry, not into the fragment coordinate. (Measured
      // on a 46mm: size 187.9x224, getTransform()[0] 1.107, dpr 2.0, and the
      // coordinate tops out at 187.9.) Feeding it device pixels instead halves
      // uv, which silently switches off `peril` — the shader's test for the
      // edge that costs a life is `dot(uv, uPerilDir) > 0.62`, and half of that
      // never gets there. The ring keeps drawing; it just stops marking the
      // edge you lose through.
      _paintRing(canvas, size, 1.0);
      return;
    }

    final double shadeScale = resolution * toDevice;
    final int w = (size.width * shadeScale).ceil();
    final int h = (size.height * shadeScale).ceil();
    if (w <= 0 || h <= 0) {
      return;
    }
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas offscreen = Canvas(recorder);
    offscreen.scale(shadeScale);
    _paintRing(offscreen, size, shadeScale);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(w, h);
    picture.dispose();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    image.dispose();
  }

  void _paintRing(Canvas canvas, Size size, double shadeScale) {
    // Everything here that does not vary across the ring is evaluated once,
    // not once per shaded pixel. The shader runs on the CPU on a watch, so a
    // `sin` of a frame-constant is thousands of identical transcendentals per
    // frame; hoisting them costs one multiply here. See the .frag header.
    final double t = seconds.value;
    final double urgency = math.max(danger, threat);
    final double breathe = 0.85 + 0.15 * math.sin(t * (2.2 + 6.0 * urgency));
    final double bandPhase = t * 6.0;
    final double hazardPhase = t * (7.0 + 12.0 * urgency);
    final double perilBoost = 0.35 + 1.5 * urgency;
    // Amber at rest, red as the situation deteriorates.
    final double hotR = 1.0;
    final double hotG = 0.55 + (0.12 - 0.55) * urgency;
    final double hotB = 0.12 + (0.16 - 0.12) * urgency;

    // Uniform indices follow declaration order in the .frag, with vectors
    // flattened: uSize.xy = 0,1 · uBandPhase = 2 · uAccent.rgb = 3,4,5 ·
    // uBreathe = 6 · uPerilBoost = 7 · uFlareP = 8..11 · uFlareI = 12..15 ·
    // uPerilDir.xy = 16,17 · uHot.rgb = 18,19,20 · uHazardPhase = 21.
    // uSize is in the shaded surface's pixels, which the offscreen scale makes
    // smaller than the widget on the watch and larger on TV. Only ratios of it
    // are used, so scaling both components leaves uv and the aspect correction
    // unchanged either way. uGuardFrac follows at 22.
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, size.width * shadeScale)
      ..setFloat(1, size.height * shadeScale)
      ..setFloat(2, bandPhase)
      ..setFloat(3, accent.r)
      ..setFloat(4, accent.g)
      ..setFloat(5, accent.b)
      ..setFloat(6, breathe)
      ..setFloat(7, perilBoost);

    // Four slots, padded with zero intensity when fewer are live.
    for (int i = 0; i < 4; i++) {
      final RingFlare? f = i < flares.length ? flares[i] : null;
      shader.setFloat(8 + i, f?.position ?? 0.0);
      shader.setFloat(12 + i, f == null ? 0.0 : f.life.clamp(0.0, 1.0));
    }

    // How far in from each end of the losing edge the paddle can travel, as a
    // fraction of that edge's run — the shader marks exactly that stretch.
    //
    // The paddle's leading coordinate is clamped to
    // `[kPaddleClamp, along - paddleWidth - kPaddleClamp]` and it spans
    // `paddleWidth`, so what it sweeps is `[kPaddleClamp, along - kPaddleClamp]`
    // with the width cancelling out — which is what makes one constant right
    // here even while an expand power-up is running.
    //
    // The paddle guards the bottom, or the right in vertical mode, so the run
    // is the other axis. Unitless, so the offscreen scale does not enter in.
    final double sizeAlong = perilAxis.dx != 0 ? size.height : size.width;
    final double guardFrac = sizeAlong <= 0
        ? 0.0
        : (kPaddleClamp / sizeAlong).clamp(0.0, 0.5);

    shader
      ..setFloat(16, perilAxis.dx)
      ..setFloat(17, perilAxis.dy)
      ..setFloat(18, hotR)
      ..setFloat(19, hotG)
      ..setFloat(20, hotB)
      ..setFloat(21, hazardPhase)
      ..setFloat(22, guardFrac);

    // Thick enough to be unmistakable from across a room, still a thin band of
    // actual shaded pixels. Sits on the same path as the painter's own border.
    final double band = math.max(4.0, size.shortestSide * 0.045);
    final Rect border = Rect.fromLTWH(
      kGameMargin,
      kGameMargin,
      size.width - 2 * kGameMargin,
      size.height - 2 * kGameMargin,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(border, Radius.circular(cornerRadius)),
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = band,
    );
    shader.dispose();
  }

  @override
  // The ticker repaints every frame regardless; flares and state are read
  // fresh out of the live game objects on each paint.
  bool shouldRepaint(_NeonPulsePainter old) => true;
}
