import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// Campaign generator: 10 worlds x 10 levels = 100 deterministic levels.
///
/// Every level is produced from a seeded RNG, so the campaign is identical on
/// every run and device — hand-authored setpieces sit at each world's midpoint
/// (x5) and boss slot (x10), and parametric patterns fill the rest.
///
/// Brick alphabet: N normal · A armored(2) · H heavy(3) · I indestructible ·
/// M slider · F fast slider · E explosive · G ghost · S shield generator.

// ---------------------------------------------------------------------------
// Worlds
// ---------------------------------------------------------------------------

class WorldSpec {
  const WorldSpec({
    required this.name,
    required this.color,
    required this.background,
    required this.spacing,
    required this.palette,
    this.slideFactor = 1.0,
  });

  final String name;
  final Color color;
  final Color background;

  /// Gap between bricks in this world (0 = pinned).
  final double spacing;

  /// Weighted brick alphabet used by the pattern fillers: entries repeat to
  /// increase their odds. Never includes 'I' — walls are placed structurally.
  final List<String> palette;

  final double slideFactor;
}

const List<WorldSpec> kWorlds = [
  WorldSpec(
    name: 'NEON',
    color: Colors.cyanAccent,
    background: Color(0xFF0A191D),
    spacing: 3.0,
    palette: ['N', 'N', 'N', 'A'],
  ),
  WorldSpec(
    name: 'FORTRESS',
    color: Colors.orangeAccent,
    background: Color(0xFF1D130A),
    spacing: 2.0,
    palette: ['N', 'N', 'A', 'A'],
  ),
  WorldSpec(
    name: 'ORBIT',
    color: Colors.tealAccent,
    background: Color(0xFF0A1D1A),
    spacing: 2.0,
    palette: ['N', 'N', 'A', 'M'],
    slideFactor: 1.0,
  ),
  WorldSpec(
    name: 'NOVA',
    color: Colors.deepOrangeAccent,
    background: Color(0xFF1F0F05),
    spacing: 1.5,
    palette: ['N', 'A', 'A', 'E'],
  ),
  WorldSpec(
    name: 'BASTION',
    color: Colors.amberAccent,
    background: Color(0xFF1F1805),
    spacing: 1.5,
    palette: ['N', 'A', 'H', 'H'],
  ),
  WorldSpec(
    name: 'PHANTOM',
    color: Colors.purpleAccent,
    background: Color(0xFF130A1D),
    spacing: 1.0,
    palette: ['N', 'A', 'G', 'G'],
  ),
  WorldSpec(
    name: 'AEGIS',
    color: Colors.lightBlueAccent,
    background: Color(0xFF0A0E1C),
    spacing: 1.0,
    palette: ['N', 'A', 'H', 'S'],
  ),
  WorldSpec(
    name: 'TEMPEST',
    color: Colors.yellowAccent,
    background: Color(0xFF1D1B0A),
    spacing: 0.5,
    palette: ['A', 'H', 'E', 'G', 'F'],
    slideFactor: 1.4,
  ),
  WorldSpec(
    name: 'SINGULARITY',
    color: Colors.pinkAccent,
    background: Color(0xFF1D0A1C),
    spacing: 0.0,
    palette: ['A', 'H', 'H', 'E', 'S'],
  ),
  WorldSpec(
    name: 'CROWN',
    color: Colors.redAccent,
    background: Color(0xFF1C0A0A),
    spacing: 0.0,
    palette: ['A', 'H', 'E', 'G', 'S', 'F'],
    slideFactor: 1.6,
  ),
];

/// Ball-speed multiplier for level [index] (0-based). Grows steadily but is
/// capped so level 100 stays playable on a 40mm screen: 1.0 -> ~1.72.
double speedFactorFor(int index) {
  final world = index ~/ 10;
  final step = index % 10;
  // The world bump (0.075) exceeds a full world of steps (9 * 0.008), so the
  // curve never dips when crossing into a new world.
  return math.min(1.72, 1.0 + world * 0.075 + step * 0.008);
}

/// Paddle-width multiplier: full size through world 4, then one step down per
/// world (min 0.84 ≈ 38px of the base 45px).
double paddleFactorFor(int index) {
  final world = index ~/ 10;
  if (world < 4) return 1.0;
  return math.max(0.84, 1.0 - (world - 3) * 0.03);
}

// ---------------------------------------------------------------------------
// Pattern kit — every function returns rows of equal width.
// ---------------------------------------------------------------------------

String _pick(math.Random rng, List<String> palette) =>
    palette[rng.nextInt(palette.length)];

List<String> _rowsToStrings(List<List<String>> grid) =>
    [for (final row in grid) row.join()];

List<List<String>> _empty(int rows, int cols) =>
    List.generate(rows, (_) => List.filled(cols, ' '));

/// Solid block with per-cell palette fill.
List<String> patternBlock(math.Random rng, List<String> palette,
    {int rows = 3, int cols = 6}) {
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      g[r][c] = _pick(rng, palette);
    }
  }
  return _rowsToStrings(g);
}

/// Checkerboard: palette on one parity, gap or weak brick on the other.
List<String> patternChecker(math.Random rng, List<String> palette,
    {int rows = 4, int cols = 7, bool fillGaps = false}) {
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if ((r + c).isEven) {
        g[r][c] = _pick(rng, palette);
      } else if (fillGaps) {
        g[r][c] = 'N';
      }
    }
  }
  return _rowsToStrings(g);
}

/// Centered pyramid, apex up.
List<String> patternPyramid(math.Random rng, List<String> palette,
    {int rows = 4}) {
  final cols = rows * 2 - 1;
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var c = rows - 1 - r; c <= rows - 1 + r; c++) {
      g[r][c] = _pick(rng, palette);
    }
  }
  return _rowsToStrings(g);
}

/// Hollow frame of [wall] bricks with a palette core.
List<String> patternFrame(math.Random rng, List<String> palette,
    {int rows = 4, int cols = 7, String wall = 'A', bool hollow = false}) {
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final edge = r == 0 || r == rows - 1 || c == 0 || c == cols - 1;
      if (edge) {
        g[r][c] = wall;
      } else if (!hollow) {
        g[r][c] = _pick(rng, palette);
      }
    }
  }
  return _rowsToStrings(g);
}

/// Vertical columns with lanes between them.
List<String> patternColumns(math.Random rng, List<String> palette,
    {int rows = 5, int columns = 3, int colWidth = 1}) {
  final cols = columns * (colWidth + 1) - 1;
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var i = 0; i < columns; i++) {
      for (var w = 0; w < colWidth; w++) {
        g[r][i * (colWidth + 1) + w] = _pick(rng, palette);
      }
    }
  }
  return _rowsToStrings(g);
}

/// Diamond (rhombus) outline filled with palette.
List<String> patternDiamond(math.Random rng, List<String> palette,
    {int half = 3, String? core}) {
  final size = half * 2 - 1;
  final g = _empty(size, size);
  for (var r = 0; r < size; r++) {
    final span = half - 1 - (r - (half - 1)).abs();
    for (var c = half - 1 - span; c <= half - 1 + span; c++) {
      g[r][c] = _pick(rng, palette);
    }
  }
  if (core != null) g[half - 1][half - 1] = core;
  return _rowsToStrings(g);
}

/// Zigzag ribbon rows.
List<String> patternZigzag(math.Random rng, List<String> palette,
    {int rows = 4, int cols = 7}) {
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if ((c + r) % 3 != 2) g[r][c] = _pick(rng, palette);
    }
  }
  return _rowsToStrings(g);
}

/// Random fill at [density], guaranteeing the result is never empty.
List<String> patternNoise(math.Random rng, List<String> palette,
    {int rows = 4, int cols = 7, double density = 0.6}) {
  final g = _empty(rows, cols);
  var placed = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if (rng.nextDouble() < density) {
        g[r][c] = _pick(rng, palette);
        placed++;
      }
    }
  }
  if (placed < 6) return patternBlock(rng, palette, rows: rows, cols: cols);
  return _rowsToStrings(g);
}

/// Two I-walls forming a tunnel with the prize behind them.
List<String> patternTunnel(math.Random rng, List<String> palette,
    {int rows = 5, int cols = 7}) {
  final g = _empty(rows, cols);
  final gap = 1 + rng.nextInt(cols - 2);
  for (var c = 0; c < cols; c++) {
    // Prize rows at the top.
    g[0][c] = _pick(rng, palette);
    g[1][c] = _pick(rng, palette);
    // Wall row with a single gap lane.
    if (c != gap) g[2][c] = 'I';
  }
  for (var c = 0; c < cols; c++) {
    if ((c + 1) % 2 == 0) g[rows - 1][c] = _pick(rng, palette);
  }
  return _rowsToStrings(g);
}

/// Concentric ring (frame within frame).
List<String> patternRings(math.Random rng, List<String> palette,
    {int rows = 5, int cols = 7, String outer = 'A'}) {
  final g = _empty(rows, cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final layer = [r, rows - 1 - r, c, cols - 1 - c].reduce(math.min);
      if (layer == 0) {
        g[r][c] = outer;
      } else if (layer == 1) {
        g[r][c] = _pick(rng, palette);
      } else {
        g[r][c] = 'E';
      }
    }
  }
  return _rowsToStrings(g);
}

// ---------------------------------------------------------------------------
// Setpieces — hand-authored mid-boss (x5) and boss (x10) layouts per world.
// World 1 keeps the original ten levels, so its entries are unused.
// ---------------------------------------------------------------------------

class _Setpiece {
  const _Setpiece(this.name, this.layout);
  final String name;
  final List<String> layout;
}

const Map<int, _Setpiece> _midBosses = {
  1: _Setpiece('KEEP', [
    'I A A A I',
    'I N N N I',
    'I A N A I',
    '  N N N  ',
  ]),
  2: _Setpiece('CAROUSEL', [
    'M M M M M',
    '  A N A  ',
    'M M M M M',
    '  N A N  ',
  ]),
  3: _Setpiece('FUSE', [
    'A A E A A',
    'A E N E A',
    'E N N N E',
  ]),
  4: _Setpiece('ANVIL', [
    'H H H H H',
    'A A A A A',
    '  H A H  ',
    '  N N N  ',
  ]),
  5: _Setpiece('SEANCE', [
    'G N G N G',
    'N G N G N',
    'G N G N G',
  ]),
  6: _Setpiece('WARDEN', [
    'A A S A A',
    'A N N N A',
    'S N A N S',
    '  N N N  ',
  ]),
  7: _Setpiece('CYCLONE', [
    'F A G A F',
    'E H N H E',
    'F A G A F',
  ]),
  8: _Setpiece('COMPRESSOR', [
    'HHHHHHH',
    'AEAEAEA',
    'HAHAHAH',
    ' ENENE ',
  ]),
  9: _Setpiece('THRONE ROOM', [
    'IGIGIGI',
    'HEHEHEH',
    'SAHAHAS',
    ' HEAEH ',
  ]),
};

const Map<int, _Setpiece> _bosses = {
  1: _Setpiece('BASTILLE', [
    'I I I I I',
    'A A A A A',
    'N A A A N',
    'N N A N N',
  ]),
  2: _Setpiece('GYROSCOPE', [
    'F F F F F',
    'A I A I A',
    'M M M M M',
    'N A A A N',
  ]),
  3: _Setpiece('SUPERNOVA', [
    'A E A E A',
    'E A E A E',
    'A E I E A',
    'E A E A E',
  ]),
  4: _Setpiece('CITADEL PRIME', [
    'I H H H I',
    'H A E A H',
    'H E H E H',
    'A N A N A',
  ]),
  5: _Setpiece('POLTERGEIST', [
    'G G A G G',
    'G H G H G',
    'A G E G A',
    'G N G N G',
  ]),
  6: _Setpiece('SANCTUM', [
    'S H A H S',
    'H E N E H',
    'A N S N A',
    'H E N E H',
  ]),
  7: _Setpiece('MAELSTROM', [
    'FGFGFGF',
    'EHSAHSE', // generators buried mid-storm
    'AHEHEHA',
    'GFN NFG',
  ]),
  8: _Setpiece('EVENT HORIZON', [
    'IHIHIHI',
    'HEHEHEH',
    'ESAHASE',
    'HHEIEHH',
    ' AHHHA ',
  ]),
  9: _Setpiece('THE CROWN', [
    'A  H  A', // crown points
    'AH H HA',
    'AHHHHHA',
    'SEHIHES',
    'HHHHHHH',
    'GEGEGEG',
  ]),
};

// ---------------------------------------------------------------------------
// Campaign assembly
// ---------------------------------------------------------------------------

/// Builds the 90 generated levels for worlds 2-10 and appends them to
/// [classicLevels] (the original ten, which remain world 1).
List<LevelData> buildCampaign(List<LevelData> classicLevels) {
  assert(classicLevels.length == 10);
  final levels = <LevelData>[...classicLevels];

  const stepNames = [
    'APPROACH', 'PATROL', 'LATTICE', 'BULWARK', // 1-4
    '', // 5 = mid-boss
    'CROSSFIRE', 'GAUNTLET', 'REDOUBT', 'ONSLAUGHT', // 6-9
    '', // 10 = boss
  ];

  for (var index = 10; index < 100; index++) {
    final world = index ~/ 10; // 1..9 here
    final step = index % 10; // 0..9
    final spec = kWorlds[world];
    final rng = math.Random(0xC0FFEE + index * 7919);

    List<String> layout;
    String name;

    if (step == 4 && _midBosses.containsKey(world)) {
      final piece = _midBosses[world]!;
      layout = piece.layout;
      name = piece.name;
    } else if (step == 9 && _bosses.containsKey(world)) {
      final piece = _bosses[world]!;
      layout = piece.layout;
      name = piece.name;
    } else {
      layout = _generatedLayout(rng, spec, world, step);
      name = '${spec.name} ${stepNames[step]}';
    }

    levels.add(LevelData(
      name: name,
      layout: layout,
      themeColor: spec.color,
      spacing: spec.spacing,
      speedFactor: speedFactorFor(index),
      paddleFactor: paddleFactorFor(index),
      slideFactor: spec.slideFactor,
    ));
  }
  return levels;
}

/// Picks a pattern for a non-setpiece slot. Rows/size scale gently with the
/// step so late levels in a world are denser than early ones.
List<String> _generatedLayout(
    math.Random rng, WorldSpec spec, int world, int step) {
  final dense = step >= 5;
  final rows = dense ? 4 + (world >= 7 ? 1 : 0) : 3 + (world >= 5 ? 1 : 0);
  final palette = spec.palette;

  final roll = (step + world) % 7;
  switch (roll) {
    case 0:
      return patternChecker(rng, palette, rows: rows, cols: 7, fillGaps: dense);
    case 1:
      return patternPyramid(rng, palette, rows: math.min(4, rows));
    case 2:
      return patternFrame(rng, palette,
          rows: rows, cols: 7, wall: world >= 4 ? 'H' : 'A', hollow: !dense);
    case 3:
      return patternColumns(rng, palette,
          rows: rows + 1, columns: dense ? 4 : 3, colWidth: dense ? 1 : 2);
    case 4:
      return patternDiamond(rng, palette,
          half: 4, core: world >= 3 ? 'E' : 'I');
    case 5:
      return world >= 2
          ? patternTunnel(rng, palette, rows: rows + 1, cols: 7)
          : patternZigzag(rng, palette, rows: rows, cols: 7);
    default:
      return world >= 3 && dense
          ? patternRings(rng, palette,
              rows: 5, cols: 7, outer: world >= 5 ? 'H' : 'A')
          : patternNoise(rng, palette,
              rows: rows, cols: 7, density: dense ? 0.75 : 0.6);
  }
}
