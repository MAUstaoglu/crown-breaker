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
  }) : super(repaint: seconds);

  final ui.FragmentProgram program;
  final ValueNotifier<double> seconds;
  final Color accent;
  final List<RingFlare> flares;
  final double danger;
  final double threat;
  final Offset perilAxis;

  /// Offscreen size per **logical** pixel of the widget.
  ///
  /// Note this is not per *device* pixel: [ui.Picture.toImageSync] takes a
  /// size in pixels while [Size] is logical, so 1.0 rasterises the ring at
  /// 416x496 on a screen that displays 832x992. The ring is therefore drawn at
  /// half device resolution and scaled up — that upscale is where the speed
  /// comes from, and it costs sharpness.
  ///
  /// Measured on an Apple Watch Series 10 (menu, profile): the direct stroke
  /// held 56.5fps with the frame fully saturated; this path holds 60.0fps with
  /// 39% of the frame idle. Values of 0.5, 0.7, 0.85 and 1.0 all cost the same
  /// on the Simulator, so 1.0 is the sharpest of the ones that are free.
  /// **2.0 — true device resolution — is far worse than not doing this at
  /// all** (13.8fps), so the offscreen only pays while it is also downscaling.
  static const double _shadeScale = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final int w = (size.width * _shadeScale).ceil();
    final int h = (size.height * _shadeScale).ceil();
    if (w <= 0 || h <= 0) {
      return;
    }
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas offscreen = Canvas(recorder);
    offscreen.scale(_shadeScale);
    _paintRing(offscreen, size);
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

  void _paintRing(Canvas canvas, Size size) {
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
    // smaller than the widget. Only ratios of it are used, so scaling both
    // components leaves uv and the aspect correction unchanged.
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, size.width * _shadeScale)
      ..setFloat(1, size.height * _shadeScale)
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

    shader
      ..setFloat(16, perilAxis.dx)
      ..setFloat(17, perilAxis.dy)
      ..setFloat(18, hotR)
      ..setFloat(19, hotG)
      ..setFloat(20, hotB)
      ..setFloat(21, hazardPhase);

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
      RRect.fromRectAndRadius(border, const Radius.circular(kGameCornerRadius)),
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
