import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Paints [shaders/neon_field.frag] behind [child], tinted to [color].
///
/// A drop-in replacement for `Container(color: …, child: …)`. If the shader
/// cannot be compiled — an engine without fragment-shader support, a bad
/// build — this falls back to the flat [color] and the game is unaffected.
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
class NeonField extends StatefulWidget {
  const NeonField({
    super.key,
    required this.color,
    required this.accent,
    required this.child,
    this.energy = 1.0,
    this.enabled = true,
  });

  /// The world's background. Also the fallback fill when the shader is
  /// unavailable.
  final Color color;

  /// The world's neon hue, added on top of [color] by the field.
  final Color accent;

  /// 0 dims the field for menus, 1 is full brightness during play.
  final double energy;

  /// Set false to paint the flat [color] and skip the shader entirely.
  final bool enabled;

  final Widget child;

  @override
  State<NeonField> createState() => _NeonFieldState();
}

class _NeonFieldState extends State<NeonField>
    with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// Seconds since this field mounted; also the painter's repaint signal.
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
    _loading ??= ui.FragmentProgram.fromAsset('shaders/neon_field.frag').then(
      (ui.FragmentProgram program) => _program = program,
      // Leave _program null on failure — build() falls back to the flat colour.
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
      return ColoredBox(color: widget.color, child: widget.child);
    }
    return CustomPaint(
      painter: _NeonFieldPainter(
        program: program,
        seconds: _seconds,
        color: widget.color,
        accent: widget.accent,
        energy: widget.energy,
      ),
      child: widget.child,
    );
  }
}

class _NeonFieldPainter extends CustomPainter {
  _NeonFieldPainter({
    required this.program,
    required this.seconds,
    required this.color,
    required this.accent,
    required this.energy,
  }) : super(repaint: seconds);

  final ui.FragmentProgram program;
  final ValueNotifier<double> seconds;
  final Color color;
  final Color accent;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform indices follow declaration order in the .frag, with vectors
    // flattened: uSize.xy = 0,1 · uTime = 2 · uBase.rgb = 3,4,5 ·
    // uAccent.rgb = 6,7,8 · uEnergy = 9.
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, seconds.value)
      ..setFloat(3, color.r)
      ..setFloat(4, color.g)
      ..setFloat(5, color.b)
      ..setFloat(6, accent.r)
      ..setFloat(7, accent.g)
      ..setFloat(8, accent.b)
      ..setFloat(9, energy);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    shader.dispose();
  }

  @override
  bool shouldRepaint(_NeonFieldPainter old) =>
      old.color != color || old.accent != accent || old.energy != energy;
}
