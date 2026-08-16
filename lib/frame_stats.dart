import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Reports raster and build timings to the device console.
///
/// This exists because DevTools cannot reach a physical Apple Watch: the Dart
/// VM Service binds loopback on the device and the CoreDevice tunnel does not
/// route TCP to it, so `rasterDuration` — the number that decides whether a
/// shader fits the frame budget — is unreachable from the host. The engine
/// still measures it; [SchedulerBinding.addTimingsCallback] hands it to us
/// in-process, and `print` reaches the terminal through the device console that
/// `flutter-watchos run` (or `flutter-tvos run`) already streams.
///
/// Samples are aggregated over [_reportEvery] rather than printed per frame.
/// One line per frame would be ~60 console writes a second on a device whose
/// logging path is slow enough to perturb the very timings being measured.
///
/// Profile builds only. Debug timings are JIT-distorted and meaningless, and a
/// release build should not log.
void installFrameStats() {
  if (!kProfileMode) {
    return;
  }
  final _FrameStats stats = _FrameStats();
  SchedulerBinding.instance.addTimingsCallback(stats.onTimings);
}

/// One 60 Hz frame's worth of budget. A raster pass longer than this missed
/// its vsync, which is what "jank" means here.
const int _budgetMicros = 16667;

const Duration _reportEvery = Duration(seconds: 1);

class _FrameStats {
  final List<int> _raster = <int>[];
  final List<int> _build = <int>[];
  final Stopwatch _sinceReport = Stopwatch()..start();

  void onTimings(List<FrameTiming> timings) {
    for (final FrameTiming t in timings) {
      _raster.add(t.rasterDuration.inMicroseconds);
      _build.add(t.buildDuration.inMicroseconds);
    }
    if (_sinceReport.elapsed < _reportEvery || _raster.isEmpty) {
      return;
    }
    _report();
    _raster.clear();
    _build.clear();
    _sinceReport.reset();
  }

  void _report() {
    final int frames = _raster.length;
    final int janky = _raster.where((int us) => us > _budgetMicros).length;
    // Sorting mutates the buffers, which is fine — they are cleared right after.
    _raster.sort();
    _build.sort();
    // ignore: avoid_print
    print(
      '[frame] ${frames}f '
      'raster p50=${_ms(_pct(_raster, 50))} '
      'p95=${_ms(_pct(_raster, 95))} '
      'max=${_ms(_raster.last)} | '
      'build p50=${_ms(_pct(_build, 50))} '
      'max=${_ms(_build.last)} | '
      'jank $janky/$frames',
    );
  }
}

/// The [p]th percentile of [sorted], by nearest-rank. Callers sort first.
int _pct(List<int> sorted, int p) {
  final int rank = (sorted.length * p / 100).ceil() - 1;
  return sorted[rank.clamp(0, sorted.length - 1)];
}

String _ms(int micros) => '${(micros / 1000).toStringAsFixed(1)}ms';
