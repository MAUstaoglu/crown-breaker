import 'package:flutter/material.dart';

/// A single brick in the playfield.
///
/// Types: 'N' normal, 'A' armored (two hits), 'H' heavy (three hits),
/// 'I' indestructible, 'M' moving (slides along the row), 'F' fast slider,
/// 'E' explosive (damages its neighbors when destroyed), 'G' ghost (phases
/// in and out of solidity), 'S' shield generator (adjacent bricks are
/// invulnerable while it lives).
class Brick {
  final int id;
  final int row;
  final int col;
  Rect rect;
  final String type;
  int lives;
  final int maxLives;
  final Color baseColor;
  Color currentColor;
  double slideOffset;
  double slideDirection;

  /// Slide amplitude/speed for 'M'/'F' bricks (pixels, pixels/sec).
  final double slideAmplitude;
  final double slideSpeed;

  /// Phase offset in seconds for 'G' bricks so the grid ripples instead of
  /// blinking in unison.
  final double phase;

  /// True while an adjacent 'S' generator protects this brick.
  bool shielded;

  Brick({
    required this.id,
    required this.row,
    required this.col,
    required this.rect,
    required this.type,
    required this.lives,
    int? maxLives,
    required this.baseColor,
    required this.currentColor,
    this.slideOffset = 0.0,
    this.slideDirection = 1.0,
    this.slideAmplitude = 10.0,
    this.slideSpeed = 25.0,
    this.phase = 0.0,
    this.shielded = false,
  }) : maxLives = maxLives ?? lives;
}

class Ball {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double speed;
  bool attached;
  double attachedOffset;

  Ball({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.speed,
    this.attached = false,
    this.attachedOffset = 0.0,
  });
}

/// A dropping power-up. Types: 'multiball', 'expand', 'shield', 'sticky', 'laser'.
class PowerUp {
  double x;
  double y;
  final String type;
  final Color color;
  final double radius = 8.0;

  PowerUp({
    required this.x,
    required this.y,
    required this.type,
    required this.color,
  });
}

class Laser {
  double x;
  double y;
  final double vx;
  final double vy;
  final double width = 2.0;
  final double height = 8.0;

  Laser({required this.x, required this.y, this.vx = 0.0, this.vy = -4.0});
}

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double life; // 1.0 -> 0.0
  final Color color;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.color,
  });
}

class FloatingScore {
  double x;
  double y;
  final int score;
  double life; // 1.0 -> 0.0

  FloatingScore({
    required this.x,
    required this.y,
    required this.score,
    required this.life,
  });
}

/// Definition of a level: its display name, brick layout, and accent color,
/// plus the difficulty knobs the campaign generator tunes per level.
///
/// Each string in [layout] is one row; each character is a brick type
/// (see [Brick]) or a space for an empty cell.
class LevelData {
  final String name;
  final List<String> layout;
  final Color themeColor;

  /// Gap between bricks in pixels. 0 = pinned (bricks touch).
  final double spacing;

  /// Multiplier applied to the base ball speed for this level.
  final double speedFactor;

  /// Multiplier applied to the paddle width (later worlds shrink it).
  final double paddleFactor;

  /// Amplitude/speed multipliers for 'M' sliders ('F' bricks get an extra
  /// boost on top of these).
  final double slideFactor;

  LevelData({
    required this.name,
    required this.layout,
    required this.themeColor,
    this.spacing = 3.0,
    this.speedFactor = 1.0,
    this.paddleFactor = 1.0,
    this.slideFactor = 1.0,
  });
}
