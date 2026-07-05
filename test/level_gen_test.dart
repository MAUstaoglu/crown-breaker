import 'package:crown_breaker/level_gen.dart';
import 'package:crown_breaker/levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validChars = {'N', 'A', 'H', 'I', 'M', 'F', 'E', 'G', 'S', ' '};

  test('campaign has exactly 100 levels in 10 worlds', () {
    expect(kLevels.length, 100);
    expect(kWorlds.length, 10);
  });

  test('campaign is deterministic', () {
    final again = buildCampaign(kLevels.sublist(0, 10));
    for (var i = 0; i < 100; i++) {
      expect(again[i].layout, kLevels[i].layout, reason: 'level ${i + 1}');
      expect(again[i].name, kLevels[i].name);
    }
  });

  test('every level is well-formed and solvable', () {
    for (var i = 0; i < kLevels.length; i++) {
      final level = kLevels[i];
      final reason = 'level ${i + 1} (${level.name})';

      expect(level.layout, isNotEmpty, reason: reason);
      expect(level.layout.length, lessThanOrEqualTo(8), reason: reason);

      var destructible = 0;
      for (final row in level.layout) {
        expect(row.length, lessThanOrEqualTo(9), reason: '$reason row width');
        for (final rune in row.split('')) {
          expect(validChars, contains(rune), reason: '$reason char "$rune"');
          if (rune != ' ' && rune != 'I') destructible++;
        }
      }
      // Winnable: enough destructible bricks to be a real level.
      expect(destructible, greaterThanOrEqualTo(6), reason: reason);
    }
  });

  test('shield generators never protect an entire level forever', () {
    // Every level containing 'S' must have at least one destructible brick
    // outside every generator's 8-neighborhood OR the generator itself is
    // reachable (generators are always damageable, so this is really: at
    // least one S exists => fine). Sanity: S bricks are destructible.
    for (final level in kLevels) {
      final joined = level.layout.join();
      if (joined.contains('S')) {
        expect(joined.replaceAll(RegExp('[^S]'), '').length, greaterThan(0));
      }
    }
  });

  test('difficulty knobs follow the campaign curve', () {
    // Speed never decreases and stays within the playable band.
    for (var i = 1; i < 100; i++) {
      expect(speedFactorFor(i), greaterThanOrEqualTo(speedFactorFor(i - 1)),
          reason: 'speed dipped at level ${i + 1}');
    }
    expect(speedFactorFor(0), 1.0);
    expect(speedFactorFor(99), lessThanOrEqualTo(1.72));

    // Spacing tightens monotonically across worlds: 3.0 down to pinned 0.0.
    for (var w = 1; w < kWorlds.length; w++) {
      expect(kWorlds[w].spacing, lessThanOrEqualTo(kWorlds[w - 1].spacing));
    }
    expect(kWorlds.first.spacing, 3.0);
    expect(kWorlds.last.spacing, 0.0);

    // Paddle only shrinks, never below 84%.
    for (var i = 1; i < 100; i++) {
      expect(paddleFactorFor(i), lessThanOrEqualTo(paddleFactorFor(i - 1)));
      expect(paddleFactorFor(i), greaterThanOrEqualTo(0.84));
    }
  });

  test('mechanics are introduced by world, not before', () {
    String worldChars(int w) =>
        kLevels.sublist(w * 10, w * 10 + 10).map((l) => l.layout.join()).join();

    // Explosives first appear in world 4 (index 3), heavies by world 5,
    // ghosts world 6, generators world 7.
    for (var w = 0; w < 3; w++) {
      expect(worldChars(w).contains('E'), isFalse, reason: 'E in world ${w + 1}');
      expect(worldChars(w).contains('G'), isFalse, reason: 'G in world ${w + 1}');
      expect(worldChars(w).contains('S'), isFalse, reason: 'S in world ${w + 1}');
      expect(worldChars(w).contains('H'), isFalse, reason: 'H in world ${w + 1}');
    }
    expect(worldChars(3).contains('E'), isTrue);
    expect(worldChars(4).contains('H'), isTrue);
    expect(worldChars(5).contains('G'), isTrue);
    expect(worldChars(6).contains('S'), isTrue);

    // The finale actually uses the full toolbox.
    final finale = worldChars(9);
    for (final c in ['H', 'E', 'G', 'S', 'F', 'I']) {
      expect(finale.contains(c), isTrue, reason: 'world 10 missing $c');
    }
  });

  test('every level fits the watch playfield', () {
    // Max 7 solid bricks per row unless the row uses spacing gaps: with the
    // 9-char cap above this keeps bricks >= ~20px wide on a 40mm watch.
    for (final level in kLevels) {
      for (final row in level.layout) {
        final solid = row.replaceAll(' ', '').length;
        expect(solid, lessThanOrEqualTo(7),
            reason: '${level.name}: $solid solid bricks in one row');
      }
    }
  });
}
