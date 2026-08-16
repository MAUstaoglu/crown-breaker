import 'dart:math' as math;

import 'package:crown_breaker/constants.dart';
import 'package:crown_breaker/game_screen.dart';
import 'package:flutter_test/flutter_test.dart';

const double _kMax = kMaxLaunchAngleDeg * math.pi / 180.0;
const double _kJitterMin = kLaunchJitterMinDeg * math.pi / 180.0;
const double _kJitterMax = kLaunchJitterMaxDeg * math.pi / 180.0;

/// A ball docked on a fresh paddle sits dead centre.
const double _kCentre = 0.5;

void main() {
  test('a centred launch is never straight, which is the whole point', () {
    final math.Random random = math.Random(7);
    for (int i = 0; i < 2000; i++) {
      final double a = launchAngle(_kCentre, random);
      expect(a.abs(), greaterThanOrEqualTo(_kJitterMin - 1e-9));
      expect(a.abs(), lessThanOrEqualTo(_kJitterMax + 1e-9));
    }
  });

  test('a centred launch goes both ways', () {
    final math.Random random = math.Random(11);
    int left = 0;
    int right = 0;
    for (int i = 0; i < 2000; i++) {
      launchAngle(_kCentre, random) < 0 ? left++ : right++;
    }
    // A fair coin over 2000 draws lands far inside this; a stuck sign does not.
    expect(left, greaterThan(700));
    expect(right, greaterThan(700));
  });

  test('two consecutive launches differ', () {
    final math.Random random = math.Random(3);
    int identical = 0;
    double previous = launchAngle(_kCentre, random);
    for (int i = 0; i < 500; i++) {
      final double a = launchAngle(_kCentre, random);
      if (a == previous) identical++;
      previous = a;
    }
    expect(identical, 0);
  });

  test('never leaves the envelope the paddle itself produces', () {
    final math.Random random = math.Random(5);
    for (int i = 0; i <= 100; i++) {
      final double hit = i / 100.0; // the full length of the paddle
      for (int n = 0; n < 50; n++) {
        final double a = launchAngle(hit, random);
        expect(a, greaterThanOrEqualTo(-_kMax - 1e-9), reason: 'hit=$hit');
        expect(a, lessThanOrEqualTo(_kMax + 1e-9), reason: 'hit=$hit');
      }
    }
  });

  test('still tracks where the ball struck the paddle', () {
    // Sticky lets the player catch and aim, so the hit point has to keep
    // dominating: jitter is a nudge, not a re-roll. Averaged over the noise,
    // one end of the paddle must still send the ball the other way from the
    // other end.
    final math.Random random = math.Random(13);
    double near = 0;
    double far = 0;
    const int n = 400;
    for (int i = 0; i < n; i++) {
      near += launchAngle(0.15, random);
      far += launchAngle(0.85, random);
    }
    near /= n;
    far /= n;
    expect(near, lessThan(0));
    expect(far, greaterThan(0));
    // The 0.7 spread in hit point is worth 0.7 * 2 * kMax; jitter averages out.
    expect(far - near, closeTo(0.7 * 2 * _kMax, _kJitterMax));
  });

  test('jitter is small next to the aiming range', () {
    // If this ever stops holding, the launch has become a coin toss rather than
    // a nudge and the sticky power-up is no longer an aiming tool.
    expect(_kJitterMax, lessThan(_kMax * 0.25));
  });
}
