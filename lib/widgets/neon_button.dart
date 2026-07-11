import 'package:flutter/material.dart';

/// Neon-outlined button used across menus and overlays.
///
/// The border thickens and the fill brightens toward [accent] while focused,
/// so the Siri Remote selection is readable from the couch on tvOS. On touch
/// platforms nothing ever focuses, so it renders exactly like the original
/// ElevatedButtons it replaces.
class NeonButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color accent;
  final Color background;
  final bool autofocus;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final double radius;

  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.accent,
    this.background = const Color(0xFF101035),
    this.autofocus = false,
    this.fontSize = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      autofocus: autofocus,
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(padding),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.12)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? Color.lerp(background, accent, 0.28)!
              : background,
        ),
        shape: WidgetStateProperty.resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(
              color: accent,
              width: states.contains(WidgetState.focused) ? 2.5 : 1.2,
            ),
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
