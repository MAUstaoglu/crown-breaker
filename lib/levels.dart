import 'package:flutter/material.dart';

import 'models.dart';

/// The ten built-in levels, in order of increasing difficulty.
final List<LevelData> kLevels = [
  LevelData(
    name: "NEON GRID",
    themeColor: Colors.cyanAccent,
    layout: [
      "N N N N N",
      "N N N N N",
    ],
  ),
  LevelData(
    name: "TWIN WALLS",
    themeColor: Colors.pinkAccent,
    layout: [
      "N A   A N",
      "N A   A N",
      "N N   N N",
    ],
  ),
  LevelData(
    name: "RETRO ALIEN",
    themeColor: Colors.lightGreenAccent,
    layout: [
      "  N   N  ",
      "N A N A N",
      "N N N N N",
      "A   A   A",
    ],
  ),
  LevelData(
    name: "SHIELDED",
    themeColor: Colors.orangeAccent,
    layout: [
      "I I I I I",
      "A A N A A",
      "N N N N N",
    ],
  ),
  LevelData(
    name: "DIAMOND",
    themeColor: Colors.purpleAccent,
    layout: [
      "    N    ",
      "  N A N  ",
      "N A I A N",
      "  N A N  ",
      "    N    ",
    ],
  ),
  LevelData(
    name: "THE SPIRAL",
    themeColor: Colors.tealAccent,
    layout: [
      "N N N N N",
      "N       N",
      "N   I   N",
      "N A A A N",
    ],
  ),
  LevelData(
    name: "SLIDERS",
    themeColor: Colors.yellowAccent,
    layout: [
      "M M M M M",
      "N A N A N",
      "M M M M M",
    ],
  ),
  LevelData(
    name: "CHECKERS",
    themeColor: Colors.amberAccent,
    layout: [
      "A N A N A",
      "N I N I N",
      "A N A N A",
    ],
  ),
  LevelData(
    name: "CITADEL",
    themeColor: Colors.indigoAccent,
    layout: [
      "I I I I I",
      "I A A A I",
      "A N A N A",
      "N N N N N",
    ],
  ),
  LevelData(
    name: "THE CROWN",
    themeColor: Colors.redAccent,
    layout: [
      "A   A   A",
      "A A A A A",
      "I I I I I",
      "N N N N N",
      "N N N N N",
    ],
  ),
];
