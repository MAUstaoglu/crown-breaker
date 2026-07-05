import 'package:flutter/material.dart';

import 'level_gen.dart';
import 'models.dart';

/// The ten classic layouts — world 1 (NEON) of the campaign. They double as
/// the onboarding arc: normal bricks, then armor, walls, and sliders.
final List<LevelData> _classicLevels = [
  _classic(0, "NEON GRID", Colors.cyanAccent, [
    "N N N N N",
    "N N N N N",
  ]),
  _classic(1, "TWIN WALLS", Colors.pinkAccent, [
    "N A   A N",
    "N A   A N",
    "N N   N N",
  ]),
  _classic(2, "RETRO ALIEN", Colors.lightGreenAccent, [
    "  N   N  ",
    "N A N A N",
    "N N N N N",
    "A   A   A",
  ]),
  _classic(3, "SHIELDED", Colors.orangeAccent, [
    "I I I I I",
    "A A N A A",
    "N N N N N",
  ]),
  _classic(4, "DIAMOND", Colors.purpleAccent, [
    "    N    ",
    "  N A N  ",
    "N A I A N",
    "  N A N  ",
    "    N    ",
  ]),
  _classic(5, "THE SPIRAL", Colors.tealAccent, [
    "N N N N N",
    "N       N",
    "N   I   N",
    "N A A A N",
  ]),
  _classic(6, "SLIDERS", Colors.yellowAccent, [
    "M M M M M",
    "N A N A N",
    "M M M M M",
  ]),
  _classic(7, "CHECKERS", Colors.amberAccent, [
    "A N A N A",
    "N I N I N",
    "A N A N A",
  ]),
  _classic(8, "CITADEL", Colors.indigoAccent, [
    "I I I I I",
    "I A A A I",
    "A N A N A",
    "N N N N N",
  ]),
  _classic(9, "FIRST CROWN", Colors.redAccent, [
    "A   A   A",
    "A A A A A",
    "I I I I I",
    "N N N N N",
    "N N N N N",
  ]),
];

LevelData _classic(int index, String name, Color color, List<String> layout) {
  return LevelData(
    name: name,
    layout: layout,
    themeColor: color,
    spacing: kWorlds[0].spacing,
    speedFactor: speedFactorFor(index),
    paddleFactor: paddleFactorFor(index),
  );
}

/// The full 100-level campaign: the ten classics (world 1) plus ninety
/// generated + hand-authored levels across worlds 2-10. Deterministic — the
/// same list on every launch.
final List<LevelData> kLevels = buildCampaign(_classicLevels);
