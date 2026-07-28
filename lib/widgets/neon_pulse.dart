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
  }) : super(repaint: seconds);

  final ui.FragmentProgram program;
  final ValueNotifier<double> seconds;
  final Color accent;
  final List<RingFlare> flares;
  final double danger;
  final double threat;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform indices follow declaration order in the .frag, with vectors
    // flattened: uSize.xy = 0,1 · uTime = 2 · uAccent.rgb = 3,4,5 ·
    // uDanger = 6 · uThreat = 7 · uFlareP = 8..11 · uFlareI = 12..15.
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, seconds.value)
      ..setFloat(3, accent.r)
      ..setFloat(4, accent.g)
      ..setFloat(5, accent.b)
      ..setFloat(6, danger)
      ..setFloat(7, threat);

    // Four slots, padded with zero intensity when fewer are live.
    for (int i = 0; i < 4; i++) {
      final RingFlare? f = i < flares.length ? flares[i] : null;
      shader.setFloat(8 + i, f?.position ?? 0.0);
      shader.setFloat(12 + i, f == null ? 0.0 : f.life.clamp(0.0, 1.0));
    }

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
