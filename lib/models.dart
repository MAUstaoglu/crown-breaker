import 'package:flutter/material.dart';

/// A single brick in the playfield.
///
/// Types: 'N' normal, 'A' armored (two hits), 'I' indestructible,
/// 'M' moving (slides horizontally).
class Brick {
  final int id;
  final int row;
  final int col;
  Rect rect;
  final String type;
  int lives;
  final Color baseColor;
  Color currentColor;
  double slideOffset;
  double slideDirection;

  Brick({
    required this.id,
    required this.row,
    required this.col,
    required this.rect,
    required this.type,
    required this.lives,
    required this.baseColor,
    required this.currentColor,
    this.slideOffset = 0.0,
    this.slideDirection = 1.0,
  });
}

class Ball {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double speed;

  Ball({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.speed,
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

/// Definition of a level: its display name, brick layout, and accent color.
///
/// Each string in [layout] is one row; each character is a brick type
/// (see [Brick]) or a space for an empty cell.
class LevelData {
  final String name;
  final List<String> layout;
  final Color themeColor;

  LevelData({
    required this.name,
    required this.layout,
    required this.themeColor,
  });
}
