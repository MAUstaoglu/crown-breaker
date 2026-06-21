import 'package:flutter/material.dart';

/// Inset of the playfield from the screen edge.
const double kGameMargin = 6.0;

/// Corner radius of the rounded playfield border.
const double kGameCornerRadius = 32.0;

/// Vertical offset where the brick grid begins (leaves room for the HUD).
const double kBrickTopMargin = 38.0;

/// Minimum distance the paddle keeps from the playfield edges.
const double kPaddleClamp = 22.0;

enum GameState { menu, levelSelect, levelIntro, playing, paused, gameOver, gameWon }

/// Background tint for a given level (1-based). Falls back to the default
/// dark background for unknown levels.
Color levelBackgroundColor(int level) {
  switch (level) {
    case 1:
      return const Color(0xFF0A191D);
    case 2:
      return const Color(0xFF1D0A1C);
    case 3:
      return const Color(0xFF0E1C0A);
    case 4:
      return const Color(0xFF1D130A);
    case 5:
      return const Color(0xFF130A1D);
    case 6:
      return const Color(0xFF0A1D1A);
    case 7:
      return const Color(0xFF1D1B0A);
    case 8:
      return const Color(0xFF1F1805);
    case 9:
      return const Color(0xFF0A0E1C);
    case 10:
      return const Color(0xFF1C0A0A);
    default:
      return const Color(0xFF03030F);
  }
}
