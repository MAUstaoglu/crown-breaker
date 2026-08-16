import 'package:flutter/material.dart';

import 'level_gen.dart';

/// Set to true to unlock all 100 levels for testing/debugging.
const bool kUnlockAllLevels = false;

/// Draw the pulsing neon ring on the playfield border. Painted as a stroke, so
/// only the ring's pixels are shaded — cheap enough for the watch, unlike a
/// full-screen effect. Still worth measuring in profile on real hardware before
/// a demo. See [NeonPulse].
const bool kNeonPulseShader = true;

/// Draw the shader comet trail behind each ball. Stroked along the ball's
/// velocity, so the shaded area is a short line and not a region.
const bool kBallTrailShader = true;

/// Fraction of the watch panel's resolution the neon ring is shaded at.
///
/// The ring is rasterised into an offscreen and scaled up. That upscale is
/// where the speed comes from and it costs sharpness, so the target is half
/// device resolution — sharp enough on a ring of glow across ~200pt of screen,
/// half the shaded pixels.
///
/// This exists because **the fragment shader runs on the CPU on a watch**, so
/// the cost is linear in shaded pixels and nothing else. Measured on an Apple
/// Watch Series 10 (menu, profile): the direct stroke held 56.5fps with the
/// frame fully saturated; this path holds 60.0fps with 39% of the frame idle.
/// True device resolution through the offscreen is far worse than not doing it
/// at all (13.8fps), so the offscreen only pays while it is also downscaling.
const double kWatchRingResolution = 0.5;

/// The same fraction on Apple TV, where it is simply 1.0.
///
/// Two reasons the watch's trade-off inverts here. The shader runs on the GPU,
/// so shaded pixels are close to free and there is nothing to buy by halving
/// them. And the panel is 3840x2160: half resolution means a 1920x1080 ring
/// scaled up 2x, which on a living-room screen reads as visibly stepped along
/// the corner arcs — the one place the ring is all curve.
///
/// At 1.0 the offscreen is skipped entirely rather than run 1:1. It would
/// otherwise allocate and blit a full-screen 4K texture every frame to draw a
/// ring, which is pure cost: the intermediate only ever earned its keep as a
/// downscale.
const double kTvRingResolution = 1.0;

/// Inset of the playfield from the screen edge.
const double kGameMargin = 6.0;

/// Corner radius of the rounded playfield border on a screen with square
/// corners — which, of the two this game ships on, is only the TV.
///
/// On a watch the border is concentric with the display's own corner instead;
/// see [ScreenMetrics.playfield]. That radius is a property of the glass and
/// varies by 70% across the lineup, so it cannot be a constant here.
const double kGameCornerRadius = 32.0;

/// Vertical offset where the brick grid begins (leaves room for the HUD).
const double kBrickTopMargin = 38.0;

/// Minimum distance the paddle keeps from the playfield edges.
const double kPaddleClamp = 22.0;

/// Widest angle a launch or a paddle bounce can leave at, measured from
/// straight-on. The paddle's hit point maps across this whole range.
const double kMaxLaunchAngleDeg = 60.0;

/// Random deviation added to a ball's *launch* angle, in degrees.
///
/// A fresh ball docks at the paddle's centre, which puts the hit point at
/// exactly 0.5 and the launch at exactly 0 — dead straight. Left alone, that
/// ball retraces the same column for as long as the paddle does not move, so
/// every attempt at a level opens identically.
///
/// The magnitude has a floor as well as a ceiling: a tenth of a degree is not
/// meaningfully different from none, and picking uniformly from zero would
/// serve up the degenerate launch often enough to still be noticed.
///
/// A paddle *bounce* is deliberately left exact — where the ball strikes the
/// paddle is the game's one aiming mechanic, and jitter there would read as the
/// controls being unreliable rather than as variety.
const double kLaunchJitterMinDeg = 3.0;
const double kLaunchJitterMaxDeg = 12.0;

/// tvOS: the game simulates in a fixed logical viewport of this height and is
/// scaled up to the TV panel (1080 logical px on Apple TV). Without this the
/// watch-tuned dimensions (45px paddle, 3.5px ball, 7px fonts) render
/// microscopic on a big screen. 220 keeps watch-like proportions: the paddle
/// spans ~11% of a 16:9 playfield, the ball scales to ~17px on screen.
const double kTvLogicalHeight = 220.0;

/// watchOS: the same fixed-viewport trick, for the opposite reason.
///
/// Watch panels run from 197pt tall (40mm) to 257pt (49mm Ultra 3). Drawn
/// straight onto the panel, every absolute number in this game — paddle width,
/// brick height, font size — is a different fraction of the screen on every
/// model, so the game reads differently and *plays* differently per watch.
/// Simulating at a fixed height and scaling to the panel makes one tuning pass
/// hold for the whole lineup.
///
/// 224 is the 44mm's height: the size everything here was tuned at, so this
/// normalises the other watches onto the existing feel rather than retuning.
const double kStageHeight = 224.0;

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
