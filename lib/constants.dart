import 'package:flutter/material.dart';

import 'level_gen.dart';

/// Set to true to unlock all 100 levels for testing/debugging.
const bool kUnlockAllLevels = false;

/// Draw the pulsing neon ring on the playfield border. Painted as a stroke, so
/// only the ring's pixels are shaded — cheap enough for the watch, unlike a
/// full-screen effect. Still worth measuring in profile on real hardware before
/// a demo. See [NeonPulse].
const bool kNeonPulseShader = true;

/// Inset of the playfield from the screen edge.
const double kGameMargin = 6.0;

/// Corner radius of the rounded playfield border.
const double kGameCornerRadius = 32.0;

/// Vertical offset where the brick grid begins (leaves room for the HUD).
const double kBrickTopMargin = 38.0;

/// Minimum distance the paddle keeps from the playfield edges.
const double kPaddleClamp = 22.0;

/// tvOS: the game simulates in a fixed logical viewport of this height and is
/// scaled up to the TV panel (1080 logical px on Apple TV). Without this the
/// watch-tuned dimensions (45px paddle, 3.5px ball, 7px fonts) render
/// microscopic on a big screen. 220 keeps watch-like proportions: the paddle
/// spans ~11% of a 16:9 playfield, the ball scales to ~17px on screen.
const double kTvLogicalHeight = 220.0;

enum GameState {
  menu,
  levelSelect,
  levelIntro,
  playing,
  paused,
  gameOver,
  gameWon,
}

/// Background tint for a given level (1-based): the level's world hue,
/// deepening slightly toward the world's boss so a world reads as one arc.
Color levelBackgroundColor(int level) {
  final index = level - 1;
  if (index < 0 || index >= kWorlds.length * 10) return const Color(0xFF03030F);
  final world = kWorlds[index ~/ 10];
  final step = index % 10;
  return Color.lerp(world.background, Colors.black, 0.06 * step)!;
}
