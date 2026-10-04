import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

/// Reports how much memory the watch will still let this process have.
///
/// Same reason [installFrameStats] exists: DevTools cannot reach a physical
/// Apple Watch, so a number only the device knows has to come out through the
/// console `flutter-watchos run` already streams.
///
/// This one is worth more than the timings. watchOS kills a process that
/// crosses its per-process limit with a bare SIGKILL — no exception, no crash
/// dialog, often not even a jetsam report — so the failure it measures is
/// invisible by construction: the app is simply gone. Dart cannot see it
/// coming either. `ProcessInfo.currentRss` omits the GPU and IOKit allocations
/// the kernel charges to the process, and this game renders through Impeller
/// on Metal, where most of the footprint IS those allocations. A run measured
/// at 111 MB of RSS was killed at 302.4 MB of real footprint.
///
/// `WatchMemory.available` is `os_proc_available_memory()`, the figure that
/// actually governs, and `WatchMemory.footprint` is `phys_footprint`, the
/// quantity jetsam compares against the limit.
///
/// **Nothing here sheds anything, on purpose.** Crown Breaker holds no cache
/// worth dropping: its two [FragmentProgram]s must not be recompiled (that
/// stalls a frame), its particle list is capped at 100, and the framework
/// clears its own image cache on the same signal without being asked. Choosing
/// a degradation policy — fewer flares, no trail shader — needs numbers from a
/// real watch first, and this is what produces them. Thresholds on this
/// project are measured rather than chosen.
///
/// Profile builds only, like the frame stats: a release build should not log.
void installMemoryStats() {
  if (!kProfileMode) {
    return;
  }
  // The Siri Remote has no jetsam limit and no flutter_watchos FFI symbols to
  // call — looking them up on Apple TV throws "symbol not found".
  if (!FlutterWatchosPlatform.isWatch) {
    return;
  }
  if (!WatchMemory.availableIsSupported) {
    // The Simulator has no limit to report against, so `available` reads 0
    // there and only the footprint means anything. Say so once rather than
    // printing a column of zeroes and letting someone read it as "no memory
    // left".
    _log('no headroom figure here (Simulator, or watchOS < 6) — footprint only');
  }
  final _MemoryStats stats = _MemoryStats()..start();
  WidgetsBinding.instance.addObserver(stats);
}

/// How often the headroom is sampled and reported.
///
/// Slower than the frame report by design. Memory moves in seconds, not
/// frames, and the console write itself is slow enough on a watch to perturb
/// what is being measured — the same reason the frame stats aggregate instead
/// of printing per frame.
const Duration _sampleEvery = Duration(seconds: 5);

class _MemoryStats with WidgetsBindingObserver {
  Timer? _timer;

  /// The least headroom seen so far. The minimum is the number that decides
  /// whether this app lives: jetsam acts on a peak, and an average hides it.
  int _lowestAvailable = -1;

  void start() {
    _timer = Timer.periodic(_sampleEvery, (_) => _sample(null));
  }

  @override
  void didHaveMemoryPressure() {
    // The most valuable line this file prints: how much room was actually left
    // when the platform decided to warn. Everything a policy might later do
    // has to be chosen against this number.
    _sample('PRESSURE');
  }

  void _sample(String? tag) {
    final int footprint = WatchMemory.footprint;
    final int available = WatchMemory.available;
    if (available > 0 && (_lowestAvailable < 0 || available < _lowestAvailable)) {
      _lowestAvailable = available;
    }
    final StringBuffer line = StringBuffer();
    if (tag != null) {
      line.write('$tag — ');
    }
    line.write('footprint ${_mb(footprint)}');
    if (WatchMemory.availableIsSupported) {
      line.write(' | available ${_mb(available)}');
      if (_lowestAvailable >= 0) {
        line.write(' (low ${_mb(_lowestAvailable)})');
      }
    }
    _log(line.toString());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

void _log(String message) {
  // ignore: avoid_print
  print('[memory] $message');
}
