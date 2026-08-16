import 'dart:math' as math;
import 'dart:ui';

import 'package:crown_breaker/constants.dart';
import 'package:crown_breaker/screen_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every watch panel the game can land on, in logical points.
const Map<String, Size> kWatchPanels = <String, Size>{
  '40mm': Size(162, 197),
  '41mm': Size(176, 215),
  '44mm': Size(184, 224),
  '42mm': Size(187, 223),
  '45mm': Size(198, 242),
  '49mm Ultra': Size(205, 251),
  '46mm': Size(208, 248),
  '49mm Ultra 3': Size(211, 257),
};

/// The display corner radii measured off Apple's framebuffer masks, in points.
/// Duplicated here on purpose: if someone edits the table in the library, this
/// test should fail rather than agree with them.
const Map<String, double> kMeasuredRadii = <String, double>{
  '40mm': 29.1,
  '41mm': 38.9,
  '44mm': 35.2,
  '42mm': 46.2,
  '45mm': 42.0,
  '49mm Ultra': 56.5,
  '46mm': 52.3,
  '49mm Ultra 3': 59.4,
};

/// Clearance between the playfield border's corner and the display's own, at
/// the diagonal — where a rounded rect inset inside a rounder one is closest to
/// escaping. Negative means the border is behind the bezel.
///
/// Both radii must be in the same space, and the border is assumed inset by
/// [kGameMargin], which puts its arc centre at `(margin + border)` from the
/// screen corner and the display's at `(display, display)`.
double _diagonalGap(double display, double border) {
  final Offset arcCentre = Offset(kGameMargin + border, kGameMargin + border);
  final Offset outermost = arcCentre - Offset(border, border) / math.sqrt2;
  return display - (outermost - Offset(display, display)).distance;
}

void main() {
  group('watch', () {
    test('every panel resolves to the same stage height', () {
      for (final MapEntry<String, Size> e in kWatchPanels.entries) {
        final ScreenMetrics m = ScreenMetrics.forPanel(e.value, isTv: false);
        expect(m.stage.height, kStageHeight, reason: e.key);
      }
    });

    test('stage widths land within 3% of each other', () {
      final List<double> widths = kWatchPanels.values
          .map((Size p) => ScreenMetrics.forPanel(p, isTv: false).stage.width)
          .toList();
      final double lo = widths.reduce(math.min);
      final double hi = widths.reduce(math.max);
      // The raw panels span 27%; normalising is the entire point.
      expect((hi - lo) / lo, lessThan(0.03));
    });

    test('corner radius comes from the measured table, in stage units', () {
      for (final MapEntry<String, Size> e in kWatchPanels.entries) {
        final ScreenMetrics m = ScreenMetrics.forPanel(e.value, isTv: false);
        final double expected = kMeasuredRadii[e.key]! / m.scale;
        expect(m.cornerRadius, closeTo(expected, 0.01), reason: e.key);
      }
    });

    test('the border keeps a constant gap from the glass on every watch', () {
      // Concentric means the gap is kGameMargin everywhere along the corner,
      // not just along the straight edges. That is the whole property.
      for (final MapEntry<String, Size> e in kWatchPanels.entries) {
        final ScreenMetrics m = ScreenMetrics.forPanel(e.value, isTv: false);
        expect(
          _diagonalGap(m.cornerRadius, m.borderRadius),
          closeTo(kGameMargin, 0.01),
          reason: e.key,
        );
      }
    });

    test('a fixed corner radius would not, and runs off an Ultra 3', () {
      // Guards the premise so this suite cannot pass for free. The old code had
      // no stage on the watch, so its 32pt radius and 6pt margin were in device
      // points against the raw panel — which is the geometry to compare.
      final Iterable<double> gaps = kWatchPanels.entries.map(
        (MapEntry<String, Size> e) =>
            _diagonalGap(kMeasuredRadii[e.key]!, kGameCornerRadius),
      );
      // From ~+9.7pt of slack on a 40mm to negative on the biggest Ultra:
      // negative means the border's corner is behind the bezel.
      expect(gaps.reduce(math.max), greaterThan(9));
      expect(gaps.reduce(math.min), lessThan(0));
      expect(
        _diagonalGap(kMeasuredRadii['49mm Ultra 3']!, kGameCornerRadius),
        lessThan(-2),
      );
    });

    test('an unrecognised panel still gets a plausible corner', () {
      final ScreenMetrics m = ScreenMetrics.forPanel(
        const Size(190, 230),
        isTv: false,
      );
      expect(m.cornerRadius, greaterThan(0));
      expect(m.borderRadius, greaterThan(0));
    });
  });

  group('tvOS is left exactly as it was', () {
    final ScreenMetrics tv = ScreenMetrics.forPanel(
      const Size(1920, 1080),
      isTv: true,
    );

    test('keeps the fixed logical viewport', () {
      expect(tv.stage.height, kTvLogicalHeight);
      expect(tv.scale, closeTo(1080 / kTvLogicalHeight, 1e-9));
    });

    test('nothing is cut, so the border radius is the design constant', () {
      expect(tv.cornerRadius, 0);
      expect(tv.borderRadius, kGameCornerRadius);
    });

    test('HUD insets match the values that used to be hardcoded', () {
      expect(tv.sideInsetFor(9, atLeast: 16, clearance: 3), 16);
      expect(tv.sideInsetFor(14, atLeast: 20, clearance: 3), 20);
      // The stats row's right edge: pause inset plus the 18pt circle and gap.
      expect(tv.sideInsetFor(9, atLeast: 16, clearance: 3) + 22, 38);
    });
  });

  group('cornerInsetAt', () {
    final ScreenMetrics ultra = ScreenMetrics.forPanel(
      kWatchPanels['49mm Ultra 3']!,
      isTv: false,
    );

    test('is zero at and beyond the corner, and maximal at the edge', () {
      expect(ultra.cornerInsetAt(0), 0);
      expect(ultra.cornerInsetAt(ultra.cornerRadius), 0);
      expect(ultra.cornerInsetAt(ultra.cornerRadius + 10), 0);
      expect(ultra.cornerInsetAt(0.5), greaterThan(0));
    });

    test('shrinks monotonically as you move away from the edge', () {
      double previous = double.infinity;
      for (double y = 1; y < ultra.cornerRadius; y += 1) {
        final double inset = ultra.cornerInsetAt(y);
        expect(inset, lessThan(previous), reason: 'at y=$y');
        previous = inset;
      }
    });

    test('puts the pause button further in on an Ultra 3 than on a 44mm', () {
      final ScreenMetrics se = ScreenMetrics.forPanel(
        kWatchPanels['44mm']!,
        isTv: false,
      );
      expect(se.sideInsetFor(9, atLeast: 16, clearance: 3), 16);
      expect(ultra.sideInsetFor(9, atLeast: 16, clearance: 3), greaterThan(20));
    });

    test('the old fixed 16pt inset would hang off an Ultra 3 full-bleed', () {
      // SafeArea used to hide this: the HUD sat ~40pt below the display's top
      // edge, nowhere near the curve. Full-bleed puts the pause circle's top at
      // y=9, where the glass on this watch is already cut well past 16pt in.
      final double cut = ultra.cornerInsetAt(9);
      expect(cut, greaterThan(16));
      expect(
        ultra.sideInsetFor(9, atLeast: 16, clearance: 3),
        greaterThan(cut),
      );
    });
  });
}
