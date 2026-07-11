import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tvos/flutter_tvos.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'constants.dart';
import 'levels.dart';
import 'models.dart';
import 'widgets/menus.dart';
import 'widgets/overlays.dart';

/// The single screen that hosts every game state — menus, level select, and
/// the live playfield. The simulation runs on a [Ticker]; rendering happens in
/// [_GamePainter], which reads this state directly each frame.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  GameState _gameState = GameState.menu;
  int _currentLevelIndex = 0;
  int _score = 0;
  int _highScore = 0;
  int _lives = 3;
  int _maxUnlockedLevel = 0;
  Map<int, int> _levelStars = {};

  // Combo tracking
  int _comboCount = 0;

  // Repaint notifier for high-performance decoupled ticks
  final GameRepaintNotifier _repaintNotifier = GameRepaintNotifier();

  // Screen constraints (set on first frame / layout)
  double _screenWidth = 200.0;
  double _screenHeight = 200.0;

  bool _verticalMode = false;

  double get _paddleX => _screenWidth - kGameMargin - paddleHeight;
  double get _paddleY => _screenHeight - kGameMargin - paddleHeight;
  double get _baseBallSpeed => 130.0 * _levels[_currentLevelIndex].speedFactor;

  /// Seconds since the level started — drives ghost-brick phasing.
  double _levelTime = 0.0;

  /// Whether a brick currently collides: 'G' bricks phase 1.6s solid /
  /// 0.8s spectral, rippling across the grid via their per-brick offset.
  bool _brickSolid(Brick b) =>
      b.type != 'G' || ((_levelTime + b.phase) % 2.4) < 1.6;

  // Paddle state
  double paddleX = 80.0;
  double targetPaddleX = 80.0;
  double paddleY = 80.0;
  double targetPaddleY = 80.0;
  double paddleWidth = 45.0;
  double paddleHeight = 8.0;
  double targetPaddleWidth = 45.0;

  double get actualPaddleX => _verticalMode ? _paddleX : paddleX;
  double get actualPaddleY => _verticalMode ? paddleY : _paddleY;

  // Power-up durations / states
  bool isStickyActive = false;
  bool isLaserActive = false;
  bool isShieldActive = false;
  double laserTimer = 0.0;
  double expandTimer = 0.0;
  bool get ballAttachedToPaddle => _balls.any((b) => b.attached);

  // Game elements
  final List<Ball> _balls = [];
  final List<Brick> _bricks = [];
  final List<PowerUp> _powerups = [];
  final List<Laser> _lasers = [];
  final List<Particle> _particles = [];
  final List<FloatingScore> _floatingScores = [];

  // Game loop ticker
  late Ticker _ticker;
  final ScrollController _levelSelectScrollController = ScrollController();
  Duration _lastElapsed = Duration.zero;

  // Juice
  double _screenShake = 0.0;
  final math.Random _random = math.Random();

  StreamSubscription<CrownRotationEvent>? _crownSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // tvOS: Siri Remote (RCU) touch listener + last touch position for delta.
  TvRemoteTouchListener? _remoteListener;
  double? _lastRemoteX;

  /// True on Apple TV. Checked once; drives viewport scaling, remote-first
  /// menus (focus/select instead of taps), and Menu-button pause.
  bool _isTv = false;

  /// Root focus node: holds focus while playing so the Menu (escape) and
  /// Play/Pause remote buttons reach [_onRootKey] instead of being dropped.
  final FocusNode _gameFocusNode = FocusNode(debugLabel: 'CrownBreakerGame');

  final List<LevelData> _levels = kLevels;

  @override
  void initState() {
    super.initState();
    _loadSaveData();

    // tvOS check must come first: Platform.isIOS is true on tvOS (iOS-family),
    // so FlutterWatchosPlatform.isIos would otherwise capture the Apple TV.
    _isTv = FlutterTvosPlatform.isTvos;
    if (_isTv) {
      // Siri Remote Menu arrives as a navigation popRoute (Android-back
      // parity), not a key event — observe it for pause / back handling.
      WidgetsBinding.instance.addObserver(this);
      // Apple TV is a landscape display — use horizontal mode like iPhone.
      _verticalMode = false;
      // Drive the paddle with the Siri Remote touch surface (the RCU analog of
      // the Digital Crown). Menus/level-select navigate via the arrow-key and
      // Select events the flutter_tvos native plugin emits, so the raw touch
      // listener only needs to handle gameplay.
      TvRemoteController.instance.init();
      _remoteListener = _onRemoteTouch;
      TvRemoteController.instance.addRawListener(_remoteListener!);
    } else if (FlutterWatchosPlatform.isIos) {
      // Default to horizontal mode on iOS (iPhone/iPad).
      _verticalMode = false;
      _initGyroscope();
    } else if (FlutterWatchosPlatform.isWatch) {
      _verticalMode = true;
      // Hide system status bar / clock on watchOS.
      WatchStatusBar.hidden = true;
      // Wire up the Digital Crown platform channel using flutter_watchos (only on Watch).
      _crownSubscription = WatchCrown.instance.rotations.listen((event) {
        if (_gameState == GameState.playing) {
          _onCrownRotated(event.delta);
        } else if (_gameState == GameState.levelSelect) {
          _onLevelSelectCrownRotated(event.delta);
        }
      });
    }

    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _crownSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    if (_remoteListener != null) {
      TvRemoteController.instance.removeRawListener(_remoteListener!);
    }
    if (_isTv) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _gameFocusNode.dispose();
    _ticker.dispose();
    _levelSelectScrollController.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  // Map Siri Remote touchpad movement onto the game, reusing the Digital
  // Crown handlers so tvOS shares the watch's paddle/scroll behavior.
  //
  // Touch coordinates are normalized to [-1, 1]; we track the delta between
  // move events (like a crown rotation delta) and scale it to screen space.
  void _onRemoteTouch(TvRemoteTouchEvent event) {
    switch (event.phase) {
      case TvRemoteTouchPhase.started:
        _lastRemoteX = event.x;
        break;
      case TvRemoteTouchPhase.move:
        final double last = _lastRemoteX ?? event.x;
        final double dx = event.x - last;
        _lastRemoteX = event.x;
        if (_gameState == GameState.playing) {
          // Horizontal swipe drives the paddle. Scale so the crown mapping
          // (delta * 0.3) covers roughly the full width on a broad swipe.
          _onCrownRotated(dx * _screenWidth * 3.0);
          _repaintNotifier.repaint();
        }
        break;
      case TvRemoteTouchPhase.ended:
      case TvRemoteTouchPhase.cancelled:
        _lastRemoteX = null;
        break;
      case TvRemoteTouchPhase.clickStart:
        // Pressing the touchpad launches a docked ball / fires lasers.
        if (_gameState == GameState.playing) {
          _onScreenTapped();
        }
        break;
      case TvRemoteTouchPhase.loc:
      case TvRemoteTouchPhase.clickEnd:
        break;
    }
  }

  // Map Digital Crown rotation onto paddle movement.
  void _onCrownRotated(double delta) {
    if (_verticalMode) {
      targetPaddleY -= delta * 0.3;
      targetPaddleY = targetPaddleY.clamp(kPaddleClamp, _screenHeight - paddleWidth - kPaddleClamp);
    } else {
      targetPaddleX += delta * 0.3;
      targetPaddleX = targetPaddleX.clamp(kPaddleClamp, _screenWidth - paddleWidth - kPaddleClamp);
    }
  }

  // Scroll the level select grid using the Digital Crown.
  void _onLevelSelectCrownRotated(double delta) {
    if (!_levelSelectScrollController.hasClients) return;
    // Positive delta means rolling crown clockwise (up/away from user), which scrolls down.
    // Negative delta means rolling counter-clockwise, which scrolls up.
    // 0.45 coefficient scales rotation delta to smooth scrolling offset changes.
    final double newOffset = (_levelSelectScrollController.offset + delta * 0.45).clamp(
      0.0,
      _levelSelectScrollController.position.maxScrollExtent,
    );
    _levelSelectScrollController.jumpTo(newOffset);
  }

  // Initialize gyroscope sensor for tilt controls.
  void _initGyroscope() {
    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      if (_gameState == GameState.playing) {
        setState(() {
          if (_verticalMode) {
            // Tilting phone forward/backward (pitch, rotation around X-axis) moves paddle up/down.
            targetPaddleY += event.x * 12.0;
            targetPaddleY = targetPaddleY.clamp(kPaddleClamp, _screenHeight - paddleWidth - kPaddleClamp);
          } else {
            // Tilting phone left/right (roll, rotation around Z-axis) moves paddle left/right.
            targetPaddleX += event.z * 12.0;
            targetPaddleX = targetPaddleX.clamp(kPaddleClamp, _screenWidth - paddleWidth - kPaddleClamp);
          }
        });
      }
    });
  }

  // Trigger tactile haptic feedback (Watch Taptic Engine or iOS HapticFeedback).
  void _sendHaptic(String type) {
    // Apple TV / Siri Remote has no haptics.
    if (FlutterTvosPlatform.isTvos) return;
    if (FlutterWatchosPlatform.isWatch) {
      switch (type) {
        case 'start':
          WatchHaptics.play(WatchHapticType.start);
          break;
        case 'click':
          WatchHaptics.play(WatchHapticType.click);
          break;
        case 'success':
          WatchHaptics.play(WatchHapticType.success);
          break;
        case 'retry':
          WatchHaptics.play(WatchHapticType.retry);
          break;
        case 'failure':
          WatchHaptics.play(WatchHapticType.failure);
          break;
        case 'stop':
          WatchHaptics.play(WatchHapticType.stop);
          break;
        default:
          WatchHaptics.play(WatchHapticType.click);
      }
    } else {
      // Haptics for iOS devices (iPhone/iPad).
      switch (type) {
        case 'start':
        case 'success':
          HapticFeedback.mediumImpact();
          break;
        case 'click':
          HapticFeedback.selectionClick();
          break;
        case 'retry':
          HapticFeedback.lightImpact();
          break;
        case 'failure':
          HapticFeedback.heavyImpact();
          break;
      }
    }
  }

  String get _savePath {
    final appDir = Directory.systemTemp.parent.path;
    return '$appDir/Documents/crown_breaker_save.json';
  }

  Future<void> _loadSaveData() async {
    try {
      final file = File(_savePath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents) as Map<String, dynamic>;
        setState(() {
          _highScore = data['highScore'] as int? ?? 0;
          _maxUnlockedLevel = (data['maxUnlockedLevel'] as int? ?? 0)
              .clamp(0, _levels.length - 1);
          final starsData = data['levelStars'] as Map<String, dynamic>?;
          if (starsData != null) {
            _levelStars = starsData.map((k, v) => MapEntry(int.parse(k), v as int));
          }
        });
      }
    } catch (_) {
      // First run or corrupted save — use defaults.
    }
  }

  Future<void> _saveData() async {
    if (_score > _highScore) {
      setState(() {
        _highScore = _score;
      });
    }
    try {
      final dir = Directory('${Directory.systemTemp.parent.path}/Documents');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/crown_breaker_save.json');
      await file.writeAsString(jsonEncode({
        'highScore': _highScore,
        'maxUnlockedLevel': _maxUnlockedLevel,
        'levelStars': _levelStars.map((k, v) => MapEntry(k.toString(), v)),
      }));
    } catch (_) {
      // Silently ignore write errors.
    }
  }

  // Build the bricks, ball, and paddle for the selected level.
  void _initLevel(int levelIdx) {
    _bricks.clear();
    _balls.clear();
    _powerups.clear();
    _lasers.clear();
    _particles.clear();
    _floatingScores.clear();

    isStickyActive = false;
    isLaserActive = false;
    isShieldActive = false;
    _comboCount = 0;
    final level = _levels[levelIdx];
    paddleWidth = 45.0 * level.paddleFactor;
    targetPaddleWidth = paddleWidth;
    _levelTime = 0.0;

    final rows = level.layout.length;

    const double brickHeight = 8.0;
    final double spacingX = level.spacing;
    final double spacingY = level.spacing;

    int brickId = 0;
    for (int r = 0; r < rows; r++) {
      final line = level.layout[r];
      final cols = line.length;
      final double brickAreaWidth = _screenWidth - (kGameMargin * 2) - 8.0;
      final double bottomMargin = _verticalMode ? 24.0 : kGameMargin;
      final double brickAreaHeight = _screenHeight - kBrickTopMargin - bottomMargin;
      final brickWidth = _verticalMode
          ? (brickAreaHeight - (spacingY * (cols - 1))) / cols
          : (brickAreaWidth - (spacingX * (cols - 1))) / cols;

      for (int c = 0; c < cols; c++) {
        final char = line[c];
        if (char == ' ') continue;

        int lives = 1;
        String type = 'N';
        Color color = level.themeColor;
        double slideAmplitude = 10.0 * level.slideFactor;
        double slideSpeed = 25.0 * level.slideFactor;
        double phase = 0.0;

        switch (char) {
          case 'A':
            type = 'A';
            lives = 2;
            color = Color.lerp(level.themeColor, Colors.white, 0.4)!;
          case 'H':
            type = 'H';
            lives = 3;
            color = Color.lerp(level.themeColor, Colors.black, 0.45)!;
          case 'I':
            type = 'I';
            lives = 9999; // Indestructible
            color = const Color(0xFF8E8E93);
          case 'M':
            type = 'M';
            color = Colors.blueAccent;
          case 'F':
            type = 'F';
            color = Colors.lightBlue.shade200;
            slideAmplitude *= 1.6;
            slideSpeed *= 1.8;
          case 'E':
            type = 'E';
            color = Colors.deepOrange;
          case 'G':
            type = 'G';
            color = Color.lerp(level.themeColor, Colors.white, 0.15)!;
            phase = (r + c) * 0.35; // Ripple, don't blink in unison.
          case 'S':
            type = 'S';
            lives = 2;
            color = const Color(0xFFF5E6A8); // Pale gold generator.
        }

        final double x = _verticalMode
            ? kGameMargin + 4.0 + r * (brickHeight + spacingX)
            : kGameMargin + 4.0 + c * (brickWidth + spacingX);
        final double y = _verticalMode
            ? kBrickTopMargin + c * (brickWidth + spacingY)
            : kBrickTopMargin + r * (brickHeight + spacingY);

        _bricks.add(
          Brick(
            id: brickId++,
            row: r,
            col: c,
            rect: _verticalMode
                ? Rect.fromLTWH(x, y, brickHeight, brickWidth)
                : Rect.fromLTWH(x, y, brickWidth, brickHeight),
            type: type,
            lives: lives,
            baseColor: color,
            currentColor: color,
            slideDirection: (r % 2 == 0) ? 1.0 : -1.0,
            slideAmplitude: slideAmplitude,
            slideSpeed: slideSpeed,
            phase: phase,
          ),
        );
      }
    }
    _recomputeShields();

    // Center the paddle and dock the starting ball on it.
    targetPaddleX = (_screenWidth - paddleWidth) / 2;
    paddleX = targetPaddleX;
    targetPaddleY = (_screenHeight - paddleWidth) / 2;
    paddleY = targetPaddleY;

    if (_verticalMode) {
      _balls.add(
        Ball(
          x: _paddleX - 3.5,
          y: _screenHeight / 2,
          vx: 0,
          vy: 0,
          radius: 3.5,
          speed: _baseBallSpeed,
          attached: true,
        ),
      );
    } else {
      _balls.add(
        Ball(
          x: _screenWidth / 2,
          y: _paddleY - 3.5,
          vx: 0,
          vy: 0,
          radius: 3.5,
          speed: _baseBallSpeed,
          attached: true,
        ),
      );
    }
    _lives = 3;
    _score = 0;
  }

  /// Selects [index], runs the level-intro splash, then starts play. Shared by
  /// the level grid, the retry button, and the next-level button.
  void _enterLevel(int index, {String haptic = "start"}) {
    _sendHaptic(haptic);
    setState(() {
      _currentLevelIndex = index;
      _initLevel(index);
      _gameState = GameState.levelIntro;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _gameState == GameState.levelIntro) {
        setState(() {
          _gameState = GameState.playing;
          _startGameLoop();
        });
        _focusGameplay();
      }
    });
  }

  /// On tvOS, park focus on the root game node while playing so no stale
  /// button keeps focus (a Select press must launch the ball, not re-activate
  /// an off-screen menu button) and Menu/Play-Pause presses reach [_onRootKey].
  void _focusGameplay() {
    if (_isTv) {
      _gameFocusNode.requestFocus();
    }
  }

  void _pauseGame() {
    _sendHaptic("click");
    setState(() {
      _gameState = GameState.paused;
      _stopGameLoop();
    });
  }

  void _resumeGame() {
    _sendHaptic("start");
    setState(() {
      _gameState = GameState.playing;
      _startGameLoop();
    });
    _focusGameplay();
  }

  /// The Siri Remote Play/Pause button (LogicalKeyboardKey.mediaPlayPause)
  /// toggles pause during gameplay.
  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (!_isTv ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.mediaPlayPause) {
      return KeyEventResult.ignored;
    }
    if (_gameState == GameState.playing) {
      _pauseGame();
      return KeyEventResult.handled;
    }
    if (_gameState == GameState.paused) {
      _resumeGame();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Siri Remote Menu button. The flutter_tvos native plugin emits it as a
  /// `popRoute` (Android-back parity), so it lands here — not as a key event.
  /// Menu pauses gameplay and steps back one screen everywhere else; returning
  /// false at the title screen lets tvOS perform its mandatory default
  /// (suspend to the home screen).
  @override
  Future<bool> didPopRoute() async {
    if (!_isTv) {
      return false;
    }
    switch (_gameState) {
      case GameState.playing:
        _pauseGame();
        return true;
      case GameState.paused:
      case GameState.gameOver:
      case GameState.gameWon:
        _sendHaptic("stop");
        _stopGameLoop();
        setState(() => _gameState = GameState.levelSelect);
        return true;
      case GameState.levelIntro:
        return true; // Swallow during the splash.
      case GameState.levelSelect:
        _sendHaptic("click");
        setState(() => _gameState = GameState.menu);
        return true;
      case GameState.menu:
        return false;
    }
  }

  void _startGameLoop() {
    _ticker.start();
    _lastElapsed = Duration.zero;
  }

  void _stopGameLoop() {
    _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    final double dt = (elapsed.inMicroseconds - _lastElapsed.inMicroseconds) / 1000000.0;
    _lastElapsed = elapsed;

    if (_gameState != GameState.playing) return;

    _updateGame(dt);
  }

  // Main physics & logic update.
  void _updateGame(double dt) {
    // 1. Decay screen shake.
    if (_screenShake > 0.0) {
      _screenShake -= dt * 15.0;
      if (_screenShake < 0.0) _screenShake = 0.0;
    }

    // 2. Animate paddle expand.
    if (paddleWidth != targetPaddleWidth) {
      final step = dt * 100.0;
      if ((paddleWidth - targetPaddleWidth).abs() < step) {
        paddleWidth = targetPaddleWidth;
      } else {
        paddleWidth += (targetPaddleWidth > paddleWidth) ? step : -step;
      }
    }

    // 2.2 Smoothly interpolate paddle position towards target.
    if (_verticalMode) {
      if (paddleY != targetPaddleY) {
        paddleY = paddleY + (targetPaddleY - paddleY) * (dt * 18.0).clamp(0.0, 1.0);
      }
    } else {
      if (paddleX != targetPaddleX) {
        paddleX = paddleX + (targetPaddleX - paddleX) * (dt * 18.0).clamp(0.0, 1.0);
      }
    }

    // 3. Update power-up timers.
    if (expandTimer > 0.0) {
      expandTimer -= dt;
      if (expandTimer <= 0.0) {
        expandTimer = 0.0;
        targetPaddleWidth = 45.0;
      }
    }
    if (laserTimer > 0.0) {
      laserTimer -= dt;
      if (laserTimer <= 0.0) {
        laserTimer = 0.0;
        setState(() {
          isLaserActive = false;
        });
      }
    }

    // 4. Level clock (ghost phasing) + moving bricks ('M' and fast 'F').
    _levelTime += dt;
    for (final brick in _bricks) {
      if (brick.type == 'M' || brick.type == 'F') {
        final step = dt * brick.slideSpeed * brick.slideDirection;
        brick.slideOffset += step;
        if (brick.slideOffset.abs() > brick.slideAmplitude) {
          brick.slideDirection *= -1.0;
        }
        // Slide along the row axis: screen-x in horizontal mode, screen-y in
        // vertical (watch) mode, where the grid is transposed.
        brick.rect = _verticalMode
            ? brick.rect.translate(0, step)
            : brick.rect.translate(step, 0);
      }
    }

    // 5. Update lasers.
    for (int i = _lasers.length - 1; i >= 0; i--) {
      final laser = _lasers[i];
      laser.x += laser.vx * 60.0 * dt;
      laser.y += laser.vy * 60.0 * dt;

      bool laserDestroyed = false;
      for (int b = _bricks.length - 1; b >= 0; b--) {
        final brick = _bricks[b];
        if (!_brickSolid(brick)) continue; // Lasers pass through ghosts.
        if (brick.rect.contains(Offset(laser.x, laser.y))) {
          _damageBrick(brick, laser.x, laser.y);
          laserDestroyed = true;
          break;
        }
      }

      if (laserDestroyed || (_verticalMode ? (laser.x < 0) : (laser.y < 0))) {
        _lasers.removeAt(i);
      }
    }

    // 6. Update balls & collisions.
    for (int i = _balls.length - 1; i >= 0; i--) {
      final ball = _balls[i];

      if (ball.attached) {
        // Keep the docked ball locked to the paddle at its offset.
        if (_verticalMode) {
          ball.x = _paddleX - ball.radius;
          ball.y = (paddleY + paddleWidth / 2 + ball.attachedOffset).clamp(paddleY, paddleY + paddleWidth);
        } else {
          ball.x = (paddleX + paddleWidth / 2 + ball.attachedOffset).clamp(paddleX, paddleX + paddleWidth);
          ball.y = _paddleY - ball.radius;
        }
        continue;
      }

      ball.x += ball.vx * ball.speed * dt;
      ball.y += ball.vy * ball.speed * dt;

      final double margin = kGameMargin;
      final double cornerRadius = kGameCornerRadius;
      final double leftCornerBound = margin + cornerRadius;
      final double rightCornerBound = _screenWidth - margin - cornerRadius;
      final double topCornerBound = margin + cornerRadius;
      final double bottomCornerBound = _screenHeight - margin - cornerRadius;

      bool inCorner = false;

      // Rounded-corner deflection, one quadrant at a time.
      if (ball.x < leftCornerBound && ball.y < topCornerBound) {
        inCorner = _deflectCorner(ball, leftCornerBound, topCornerBound, cornerRadius);
      } else if (ball.x > rightCornerBound && ball.y < topCornerBound) {
        inCorner = _deflectCorner(ball, rightCornerBound, topCornerBound, cornerRadius);
      } else if (ball.x < leftCornerBound && ball.y > bottomCornerBound) {
        inCorner = _deflectCorner(ball, leftCornerBound, bottomCornerBound, cornerRadius);
      } else if (ball.x > rightCornerBound && ball.y > bottomCornerBound) {
        inCorner = _deflectCorner(ball, rightCornerBound, bottomCornerBound, cornerRadius);
      }

      // Flat wall collisions when not inside a corner.
      if (!inCorner) {
        if (_verticalMode) {
          if (ball.x - ball.radius < margin) {
            ball.x = margin + ball.radius;
            ball.vx = -ball.vx;
            _sendHaptic("click");
          }
          if (ball.y - ball.radius < margin) {
            ball.y = margin + ball.radius;
            ball.vy = -ball.vy;
            _sendHaptic("click");
          } else if (ball.y + ball.radius > _screenHeight - margin) {
            ball.y = _screenHeight - margin - ball.radius;
            ball.vy = -ball.vy;
            _sendHaptic("click");
          }
        } else {
          if (ball.x - ball.radius < margin) {
            ball.x = margin + ball.radius;
            ball.vx = -ball.vx;
            _sendHaptic("click");
          } else if (ball.x + ball.radius > _screenWidth - margin) {
            ball.x = _screenWidth - margin - ball.radius;
            ball.vx = -ball.vx;
            _sendHaptic("click");
          }

          if (ball.y - ball.radius < margin) {
            ball.y = margin + ball.radius;
            ball.vy = -ball.vy;
            _sendHaptic("click");
          }
        }
      }

      // Shield bounce along the paddle line.
      bool shieldTriggered = _verticalMode
          ? (isShieldActive && ball.x + ball.radius >= _paddleX)
          : (isShieldActive && ball.y + ball.radius >= _paddleY);

      if (shieldTriggered) {
        if (_verticalMode) {
          ball.x = _paddleX - ball.radius;
          ball.vx = -ball.vx;
        } else {
          ball.y = _paddleY - ball.radius;
          ball.vy = -ball.vy;
        }
        isShieldActive = false; // Consume shield.
        _sendHaptic("success");
        _screenShake = 4.0;
        continue;
      }

      // Ball lost past the floor / right edge.
      bool outOfBounds = _verticalMode
          ? (ball.x - ball.radius > _screenWidth)
          : (ball.y - ball.radius > _screenHeight);

      if (!ball.attached && outOfBounds) {
        _balls.removeAt(i);
        continue;
      }

      // Paddle collision.
      final paddleRect = _verticalMode
          ? Rect.fromLTWH(_paddleX, paddleY, paddleHeight, paddleWidth)
          : Rect.fromLTWH(paddleX, _paddleY, paddleWidth, paddleHeight);

      bool collidesWithPaddle = false;
      if (_verticalMode) {
        collidesWithPaddle = ball.vx > 0 &&
            ball.x + ball.radius >= paddleRect.left &&
            ball.x - ball.radius <= paddleRect.right &&
            ball.y + ball.radius >= paddleRect.top &&
            ball.y - ball.radius <= paddleRect.bottom;
      } else {
        collidesWithPaddle = ball.vy > 0 &&
            ball.y + ball.radius >= paddleRect.top &&
            ball.y - ball.radius <= paddleRect.bottom &&
            ball.x + ball.radius >= paddleRect.left &&
            ball.x - ball.radius <= paddleRect.right;
      }

      if (collidesWithPaddle) {
        _sendHaptic("click");
        _screenShake = 2.0;
        // Gradually increase ball speed for tension.
        ball.speed = (ball.speed + 2.0).clamp(_baseBallSpeed, math.max(_baseBallSpeed + 40.0, 220.0));
        _comboCount = 0; // Reset combo on paddle hit.

        if (isStickyActive) {
          setState(() {
            ball.attached = true;
            if (_verticalMode) {
              ball.attachedOffset = ball.y - (paddleY + paddleWidth / 2);
            } else {
              ball.attachedOffset = ball.x - (paddleX + paddleWidth / 2);
            }
          });
          ball.vx = 0;
          ball.vy = 0;
          _sendHaptic("retry");
        } else {
          if (_verticalMode) {
            final hitPoint = (ball.y - paddleRect.top) / paddleRect.height;
            final angle = (hitPoint - 0.5) * 2.0 * (math.pi / 3.0);
            ball.vx = -math.cos(angle);
            ball.vy = math.sin(angle);
          } else {
            final hitPoint = (ball.x - paddleRect.left) / paddleRect.width;
            final angle = (hitPoint - 0.5) * 2.0 * (math.pi / 3.0);
            ball.vx = math.sin(angle);
            ball.vy = -math.cos(angle);
          }
        }
        continue;
      }

      // Brick collisions.
      for (int b = _bricks.length - 1; b >= 0; b--) {
        final brick = _bricks[b];
        if (!_brickSolid(brick)) continue; // Phased-out ghost: fly through.
        if (_checkBallBrickCollision(ball, brick)) {
          _sendHaptic("click");
          _damageBrick(brick, ball.x, ball.y);
          // Nudge the ball away to avoid oscillating between adjacent bricks.
          ball.x += ball.vx * 2.0;
          ball.y += ball.vy * 2.0;
          break; // One brick per frame.
        }
      }
    }

    // 7. Life lost / game over.
    if (_balls.isEmpty) {
      setState(() {
        _lives--;
      });
      _sendHaptic("failure");
      _screenShake = 8.0;

      if (_lives <= 0) {
        setState(() {
          _gameState = GameState.gameOver;
        });
        _saveData();
        _stopGameLoop();
      } else {
        // Re-dock a fresh ball.
        if (_verticalMode) {
          _balls.add(
            Ball(
              x: _paddleX - 3.5,
              y: paddleY + paddleWidth / 2,
              vx: 0,
              vy: 0,
              radius: 3.5,
              speed: _baseBallSpeed,
              attached: true,
            ),
          );
        } else {
          _balls.add(
            Ball(
              x: paddleX + paddleWidth / 2,
              y: _paddleY - 3.5,
              vx: 0,
              vy: 0,
              radius: 3.5,
              speed: _baseBallSpeed,
              attached: true,
            ),
          );
        }
      }
    }

    // 8. Update power-ups.
    for (int p = _powerups.length - 1; p >= 0; p--) {
      final pu = _powerups[p];
      if (_verticalMode) {
        pu.x += dt * 45.0;
      } else {
        pu.y += dt * 45.0;
      }

      final paddleRect = _verticalMode
          ? Rect.fromLTWH(_paddleX, paddleY, paddleHeight, paddleWidth)
          : Rect.fromLTWH(paddleX, _paddleY, paddleWidth, paddleHeight);

      if (pu.y + pu.radius >= paddleRect.top &&
          pu.y - pu.radius <= paddleRect.bottom &&
          pu.x + pu.radius >= paddleRect.left &&
          pu.x - pu.radius <= paddleRect.right) {
        _activatePowerUp(pu);
        _sendHaptic("retry");
        _powerups.removeAt(p);
        continue;
      }

      bool puOutOfBounds = _verticalMode
          ? (pu.x - pu.radius > _screenWidth)
          : (pu.y - pu.radius > _screenHeight);

      if (puOutOfBounds) {
        _powerups.removeAt(p);
      }
    }

    // 9. Update particles.
    for (int p = _particles.length - 1; p >= 0; p--) {
      final particle = _particles[p];
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particle.life -= dt * 1.8;
      if (particle.life <= 0.0) {
        _particles.removeAt(p);
      }
    }

    // 10. Update floating scores.
    for (int s = _floatingScores.length - 1; s >= 0; s--) {
      final fs = _floatingScores[s];
      fs.y -= dt * 20.0;
      fs.life -= dt * 1.5;
      if (fs.life <= 0.0) {
        _floatingScores.removeAt(s);
      }
    }

    // 11. Victory check.
    final hasBreakableBricks = _bricks.any((b) => b.type != 'I');
    if (!hasBreakableBricks && _gameState == GameState.playing) {
      _sendHaptic("success");
      if (_currentLevelIndex + 1 > _maxUnlockedLevel) {
        _maxUnlockedLevel = (_currentLevelIndex + 1).clamp(0, _levels.length - 1);
      }
      final stars = _lives.clamp(1, 3);
      if (stars > (_levelStars[_currentLevelIndex] ?? 0)) {
        _levelStars[_currentLevelIndex] = stars;
      }
      setState(() {
        _gameState = GameState.gameWon;
      });
      _saveData();
      _stopGameLoop();
    }

    _repaintNotifier.repaint();
  }

  // Reflect [ball] off a rounded corner centered at ([cx], [cy]). Returns true
  // when the ball was inside that corner quadrant.
  bool _deflectCorner(Ball ball, double cx, double cy, double cornerRadius) {
    final dx = ball.x - cx;
    final dy = ball.y - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final limit = cornerRadius - ball.radius;
    if (dist > limit && dist > 0) {
      final nx = dx / dist;
      final ny = dy / dist;
      ball.x = cx + nx * limit;
      ball.y = cy + ny * limit;
      final dot = ball.vx * nx + ball.vy * ny;
      ball.vx = ball.vx - 2 * dot * nx;
      ball.vy = ball.vy - 2 * dot * ny;
      _sendHaptic("click");
    }
    return true;
  }

  // Ball vs brick collision with axis-aligned resolution.
  bool _checkBallBrickCollision(Ball ball, Brick brick) {
    final rect = brick.rect;

    final closestX = ball.x.clamp(rect.left, rect.right);
    final closestY = ball.y.clamp(rect.top, rect.bottom);

    final dx = ball.x - closestX;
    final dy = ball.y - closestY;
    final distanceSquared = (dx * dx) + (dy * dy);

    if (distanceSquared < ball.radius * ball.radius) {
      final overlapX = ball.radius - (ball.x - closestX).abs();
      final overlapY = ball.radius - (ball.y - closestY).abs();

      if (overlapX < overlapY) {
        ball.vx = -ball.vx;
        ball.x += (ball.vx > 0) ? overlapX : -overlapX;
      } else {
        ball.vy = -ball.vy;
        ball.y += (ball.vy > 0) ? overlapY : -overlapY;
      }
      return true;
    }
    return false;
  }

  /// Marks every brick adjacent (8-neighborhood) to a living 'S' generator as
  /// shielded. Called at level start and whenever a generator dies.
  void _recomputeShields() {
    final generators = _bricks.where((b) => b.type == 'S' && b.lives > 0).toList();
    for (final brick in _bricks) {
      brick.shielded = brick.type != 'S' &&
          brick.type != 'I' &&
          generators.any((g) =>
              (g.row - brick.row).abs() <= 1 && (g.col - brick.col).abs() <= 1);
    }
  }

  /// Explosive chain: damages the four orthogonal grid neighbors of a dying
  /// 'E' brick. Chains recurse through neighboring explosives.
  void _explodeNeighbors(Brick source) {
    _screenShake = math.max(_screenShake, 4.0);
    final neighbors = _bricks
        .where((b) =>
            b != source &&
            ((b.row - source.row).abs() + (b.col - source.col).abs()) == 1)
        .toList();
    for (final n in neighbors) {
      _damageBrick(n, n.rect.center.dx, n.rect.center.dy);
    }
  }

  // Damage or destroy a brick and award score, particles, and power-ups.
  void _damageBrick(Brick brick, double hitX, double hitY) {
    if (brick.type == 'I' || brick.lives <= 0) return; // Indestructible or gone.
    if (brick.shielded) {
      // A generator protects this brick — ping off it, no damage.
      _spawnExplosion(hitX, hitY, Colors.white70, count: 3);
      return;
    }

    brick.lives--;
    _comboCount++;
    final comboMult = _comboCount.clamp(1, 5);
    if (brick.lives <= 0) {
      _bricks.remove(brick);
      final pts = 100 * comboMult;
      setState(() {
        _score += pts;
      });
      _floatingScores.add(FloatingScore(x: brick.rect.center.dx, y: brick.rect.center.dy, score: pts, life: 1.0));
      _spawnExplosion(brick.rect.center.dx, brick.rect.center.dy, brick.baseColor,
          count: brick.type == 'E' ? 20 : 12);

      if (brick.type == 'E') _explodeNeighbors(brick);
      if (brick.type == 'S') _recomputeShields();

      if (_random.nextDouble() < 0.20) {
        _spawnPowerUp(brick.rect.center.dx, brick.rect.center.dy);
      }
    } else {
      // Damaged multi-hit brick brightens toward the theme color per hit.
      final progress = (brick.maxLives - brick.lives) / brick.maxLives;
      brick.currentColor = brick.type == 'A'
          ? _levels[_currentLevelIndex].themeColor
          : Color.lerp(brick.baseColor, _levels[_currentLevelIndex].themeColor,
              progress)!;
      final pts = 50 * comboMult;
      setState(() {
        _score += pts;
      });
      _floatingScores.add(FloatingScore(x: brick.rect.center.dx, y: brick.rect.center.dy, score: pts, life: 1.0));
      _spawnExplosion(hitX, hitY, brick.baseColor, count: 4);
    }
  }

  void _spawnExplosion(double x, double y, Color color, {int count = 12}) {
    // Cap total particles to protect the frame rate.
    const maxParticles = 100;
    while (_particles.length + count > maxParticles && _particles.isNotEmpty) {
      _particles.removeAt(0);
    }
    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2.0 * math.pi;
      final speed = 20.0 + _random.nextDouble() * 40.0;
      _particles.add(
        Particle(
          x: x,
          y: y,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          size: 2.0 + _random.nextDouble() * 2.0,
          life: 1.0,
          color: color,
        ),
      );
    }
  }

  void _spawnPowerUp(double x, double y) {
    final types = ['multiball', 'expand', 'shield', 'sticky', 'laser'];
    final type = types[_random.nextInt(types.length)];
    Color color = Colors.white;

    switch (type) {
      case 'multiball':
        color = Colors.greenAccent;
        break;
      case 'expand':
        color = Colors.cyanAccent;
        break;
      case 'shield':
        color = Colors.blueAccent;
        break;
      case 'sticky':
        color = Colors.orangeAccent;
        break;
      case 'laser':
        color = Colors.redAccent;
        break;
    }

    _powerups.add(PowerUp(x: x, y: y, type: type, color: color));
  }

  void _activatePowerUp(PowerUp pu) {
    switch (pu.type) {
      case 'multiball':
        // Spawn three extra balls with random launch angles.
        for (int i = 0; i < 3; i++) {
          final angle = -math.pi / 4 + _random.nextDouble() * (math.pi / 2);
          if (_verticalMode) {
            _balls.add(
              Ball(
                x: _paddleX - 4.0,
                y: paddleY + paddleWidth / 2,
                vx: -math.cos(angle),
                vy: math.sin(angle),
                radius: 3.5,
                speed: _baseBallSpeed,
              ),
            );
          } else {
            _balls.add(
              Ball(
                x: paddleX + paddleWidth / 2,
                y: _paddleY - 4.0,
                vx: math.sin(angle),
                vy: -math.cos(angle),
                radius: 3.5,
                speed: _baseBallSpeed,
              ),
            );
          }
        }
        break;
      case 'expand':
        targetPaddleWidth = 65.0;
        expandTimer = 7.5;
        break;
      case 'shield':
        isShieldActive = true;
        break;
      case 'sticky':
        isStickyActive = true;
        break;
      case 'laser':
        setState(() {
          isLaserActive = true;
          laserTimer = 7.5;
        });
        break;
    }
  }

  // Fire a laser pair from the paddle edges.
  void _fireLasers() {
    if (!isLaserActive || _gameState != GameState.playing) return;
    _sendHaptic("click");
    if (_verticalMode) {
      _lasers.add(Laser(x: _paddleX - 2.0, y: paddleY + 4.0, vx: -4.0, vy: 0.0));
      _lasers.add(Laser(x: _paddleX - 2.0, y: paddleY + paddleWidth - 4.0, vx: -4.0, vy: 0.0));
    } else {
      _lasers.add(Laser(x: paddleX + 4.0, y: _paddleY - 2.0, vx: 0.0, vy: -4.0));
      _lasers.add(Laser(x: paddleX + paddleWidth - 4.0, y: _paddleY - 2.0, vx: 0.0, vy: -4.0));
    }
  }

  // Tap launches a docked ball, otherwise fires lasers.
  void _onScreenTapped() {
    if (_gameState == GameState.playing) {
      if (ballAttachedToPaddle && _balls.isNotEmpty) {
        setState(() {
          isStickyActive = false; // Consume sticky.
          for (final ball in _balls) {
            if (ball.attached) {
              ball.attached = false;
              if (_verticalMode) {
                final hitPoint = (ball.y - paddleY) / paddleWidth;
                final angle = (hitPoint - 0.5) * 2.0 * (math.pi / 3.0);
                ball.vx = -math.cos(angle);
                ball.vy = math.sin(angle);
              } else {
                final hitPoint = (ball.x - paddleX) / paddleWidth;
                final angle = (hitPoint - 0.5) * 2.0 * (math.pi / 3.0);
                ball.vx = math.sin(angle);
                ball.vy = -math.cos(angle);
              }
              ball.speed = _baseBallSpeed;
            }
          }
          _sendHaptic("start");
        });
      } else if (isLaserActive) {
        _fireLasers();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // On TV the simulation runs in a fixed logical viewport
            // (kTvLogicalHeight tall, same aspect as the panel) and the whole
            // scene — canvas, HUD, menus — is scaled up by FittedBox below.
            // Elsewhere the viewport is simply the physical screen.
            final double tvScale =
                _isTv ? constraints.maxHeight / kTvLogicalHeight : 1.0;
            final double viewWidth = constraints.maxWidth / tvScale;
            final double viewHeight = constraints.maxHeight / tvScale;

            // Capture the (logical) viewport size on first layout / resize.
            if (_screenWidth != viewWidth || _screenHeight != viewHeight) {
              _screenWidth = viewWidth;
              _screenHeight = viewHeight;
              if (_gameState == GameState.playing && ballAttachedToPaddle && _balls.isNotEmpty) {
                if (_verticalMode) {
                  targetPaddleY = (_screenHeight - paddleWidth) / 2;
                  paddleY = targetPaddleY;
                } else {
                  targetPaddleX = (_screenWidth - paddleWidth) / 2;
                  paddleX = targetPaddleX;
                }
                for (final ball in _balls) {
                  if (ball.attached) {
                    if (_verticalMode) {
                      ball.x = _paddleX - ball.radius;
                      ball.y = paddleY + paddleWidth / 2 + ball.attachedOffset;
                    } else {
                      ball.x = paddleX + paddleWidth / 2 + ball.attachedOffset;
                      ball.y = _paddleY - ball.radius;
                    }
                  }
                }
              }
            }

            return Focus(
              focusNode: _gameFocusNode,
              onKeyEvent: _onRootKey,
              // SizedBox.expand forces the FittedBox to the full screen —
              // under Center's loose constraints it would shrink-wrap the
              // logical viewport and render unscaled.
              child: SizedBox.expand(
                child: FittedBox(
                  // Logical viewport and panel share an aspect ratio, so fill
                  // == uniform scale (no distortion, no letterbox). A no-op
                  // off-TV where the child already matches the constraints.
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: _screenWidth,
                    height: _screenHeight,
                    child: Container(
                      color: levelBackgroundColor(_currentLevelIndex + 1),
                  child: Stack(
                    children: [
                      // Interactive playfield canvas.
                      if (_gameState == GameState.playing ||
                          _gameState == GameState.paused ||
                          _gameState == GameState.levelIntro)
                        GestureDetector(
                          onTap: _onScreenTapped,
                          onPanUpdate: (details) {
                            if (_gameState != GameState.playing) return;
                            if (_verticalMode) {
                              targetPaddleY += details.delta.dy;
                              targetPaddleY = targetPaddleY.clamp(kPaddleClamp, _screenHeight - paddleWidth - kPaddleClamp);
                              paddleY = targetPaddleY;
                              for (final ball in _balls) {
                                if (ball.attached) {
                                  ball.y = paddleY + paddleWidth / 2 + ball.attachedOffset;
                                }
                              }
                            } else {
                              targetPaddleX += details.delta.dx;
                              targetPaddleX = targetPaddleX.clamp(kPaddleClamp, _screenWidth - paddleWidth - kPaddleClamp);
                              paddleX = targetPaddleX; // Instant touch response.
                              for (final ball in _balls) {
                                if (ball.attached) {
                                  ball.x = paddleX + paddleWidth / 2 + ball.attachedOffset;
                                }
                              }
                            }
                            _repaintNotifier.repaint();
                          },
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(_screenWidth, _screenHeight),
                              painter: _GamePainter(state: this, repaint: _repaintNotifier),
                            ),
                          ),
                        ),

                      // State-specific overlays.
                      if (_gameState == GameState.menu)
                        MenuView(
                          highScore: _highScore,
                          verticalMode: _verticalMode,
                          // TV is always landscape; hide the orientation toggle.
                          showModeToggle: !_isTv,
                          onPlay: () {
                            _sendHaptic("click");
                            setState(() => _gameState = GameState.levelSelect);
                          },
                          onToggleMode: () {
                            _sendHaptic("click");
                            setState(() => _verticalMode = !_verticalMode);
                          },
                        ),
                      if (_gameState == GameState.levelSelect)
                        LevelSelectView(
                          levels: _levels,
                          maxUnlockedLevel: _maxUnlockedLevel,
                          levelStars: _levelStars,
                          controller: _levelSelectScrollController,
                          onSelect: (index) => _enterLevel(index),
                          onBack: () {
                            _sendHaptic("click");
                            setState(() => _gameState = GameState.menu);
                          },
                        ),
                      if (_gameState == GameState.levelIntro)
                        LevelIntroView(
                          levelIndex: _currentLevelIndex,
                          level: _levels[_currentLevelIndex],
                        ),
                      if (_gameState == GameState.playing || _gameState == GameState.paused)
                        PlayingHud(
                          levelIndex: _currentLevelIndex,
                          themeColor: _levels[_currentLevelIndex].themeColor,
                          lives: _lives,
                          score: _score,
                          comboCount: _comboCount,
                          showLaunchHint: ballAttachedToPaddle,
                          showLaserHint: isLaserActive && !ballAttachedToPaddle,
                          isTv: _isTv,
                          onPause: _pauseGame,
                        ),
                      if (_gameState == GameState.paused)
                        PausedView(
                          onResume: _resumeGame,
                          onQuit: () {
                            _sendHaptic("stop");
                            setState(() => _gameState = GameState.levelSelect);
                          },
                        ),
                      if (_gameState == GameState.gameOver)
                        GameOverView(
                          score: _score,
                          onRetry: () => _enterLevel(_currentLevelIndex, haptic: "retry"),
                          onMenu: () {
                            _sendHaptic("click");
                            setState(() => _gameState = GameState.levelSelect);
                          },
                        ),
                      if (_gameState == GameState.gameWon)
                        GameWonView(
                          score: _score,
                          lives: _lives,
                          hasNextLevel: _currentLevelIndex < _levels.length - 1,
                          onNext: () => _enterLevel(_currentLevelIndex + 1),
                          onMenu: () {
                            _sendHaptic("click");
                            setState(() => _gameState = GameState.levelSelect);
                          },
                        ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Renders the entire playfield each frame. Reads [state] directly to avoid
/// per-frame allocations; all [Paint] objects are cached.
class _GamePainter extends CustomPainter {
  final _GameScreenState state;

  final Paint _borderPaint = Paint();
  final Paint _fillPaint = Paint();
  final Paint _strokePaint = Paint();
  final Paint _crackPaint = Paint();
  final Paint _shieldPaint = Paint();
  final Paint _paddlePaint = Paint();
  final Paint _paddleGlowPaint = Paint();
  final Paint _ballPaint = Paint();
  final Paint _ballGlowPaint = Paint();
  final Paint _powerUpOuterPaint = Paint();
  final Paint _powerUpInnerPaint = Paint();
  final Paint _laserPaint = Paint();
  final Paint _particlePaint = Paint();

  _GamePainter({required this.state, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random();

    if (state._screenShake > 0.1) {
      final dx = (rand.nextDouble() - 0.5) * state._screenShake;
      final dy = (rand.nextDouble() - 0.5) * state._screenShake;
      canvas.translate(dx, dy);
    }

    final themeColor = state._levels[state._currentLevelIndex].themeColor;

    // Rounded neon playfield border.
    _borderPaint
      ..color = themeColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = null;
    final borderRect = Rect.fromLTWH(kGameMargin, kGameMargin, size.width - 2 * kGameMargin, size.height - 2 * kGameMargin);
    final borderRRect = RRect.fromRectAndRadius(borderRect, const Radius.circular(kGameCornerRadius));
    canvas.drawRRect(borderRRect, _borderPaint);

    // 1. Bricks.
    for (final brick in state._bricks) {
      // Ghost bricks fade toward transparency while phased out.
      final bool solid = state._brickSolid(brick);
      final double ghostAlpha = brick.type == 'G' ? (solid ? 0.95 : 0.22) : 1.0;

      _fillPaint
        ..color = brick.currentColor.withValues(
            alpha: brick.currentColor.a * ghostAlpha)
        ..style = PaintingStyle.fill
        ..maskFilter = null;

      final RRect rrect = RRect.fromRectAndRadius(brick.rect, const Radius.circular(2.5));
      canvas.drawRRect(rrect, _fillPaint);

      _strokePaint
        ..color = (brick.type == 'I')
            ? Colors.white54
            : brick.baseColor.withValues(alpha: 0.9 * ghostAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..maskFilter = null;
      canvas.drawRRect(rrect, _strokePaint);

      // Shield-generator halo, and a white shimmer on protected bricks.
      if (brick.type == 'S') {
        final pulse = 0.5 + 0.5 * math.sin(state._levelTime * 4.0);
        _strokePaint
          ..color = const Color(0xFFF5E6A8).withValues(alpha: 0.35 + 0.3 * pulse)
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3.0);
        canvas.drawRRect(rrect.inflate(1.5), _strokePaint);
        _strokePaint.maskFilter = null;
      } else if (brick.shielded) {
        _strokePaint
          ..color = Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = 0.8;
        canvas.drawRRect(rrect.deflate(0.5), _strokePaint);
      }

      // Explosive core dot.
      if (brick.type == 'E') {
        _fillPaint..color = Colors.yellowAccent..style = PaintingStyle.fill;
        canvas.drawCircle(brick.rect.center, 1.6, _fillPaint);
      }

      // Heavy bricks carry two rivet notches; they brighten as they crack.
      if (brick.type == 'H') {
        _fillPaint..color = Colors.white38..style = PaintingStyle.fill;
        canvas.drawCircle(
            Offset(brick.rect.left + 3, brick.rect.center.dy), 0.9, _fillPaint);
        canvas.drawCircle(
            Offset(brick.rect.right - 3, brick.rect.center.dy), 0.9, _fillPaint);
      }

      // Crack overlay for damaged armored bricks.
      if (brick.type == 'A' && brick.lives == 1) {
        _crackPaint
          ..color = Colors.black54
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke
          ..maskFilter = null;

        final path = Path()
          ..moveTo(brick.rect.left + 2, brick.rect.top + 2)
          ..lineTo(brick.rect.center.dx, brick.rect.center.dy)
          ..lineTo(brick.rect.right - 3, brick.rect.bottom - 2)
          ..moveTo(brick.rect.center.dx, brick.rect.center.dy)
          ..lineTo(brick.rect.left + 5, brick.rect.bottom - 1);
        canvas.drawPath(path, _crackPaint);
      }
    }

    // 2. Shield floor.
    if (state.isShieldActive) {
      _shieldPaint
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4.0);

      if (state._verticalMode) {
        canvas.drawLine(
          Offset(state.actualPaddleX, kGameMargin),
          Offset(state.actualPaddleX, size.height - kGameMargin),
          _shieldPaint,
        );
      } else {
        canvas.drawLine(
          Offset(kGameMargin, state.actualPaddleY),
          Offset(size.width - kGameMargin, state.actualPaddleY),
          _shieldPaint,
        );
      }
    }

    // 3. Paddle.
    final paddleRect = state._verticalMode
        ? Rect.fromLTWH(state.actualPaddleX, state.actualPaddleY, state.paddleHeight, state.paddleWidth)
        : Rect.fromLTWH(state.actualPaddleX, state.actualPaddleY, state.paddleWidth, state.paddleHeight);
    final paddleRRect = RRect.fromRectAndRadius(paddleRect, const Radius.circular(4));

    _paddlePaint
      ..color = themeColor
      ..style = PaintingStyle.fill
      ..maskFilter = null;
    canvas.drawRRect(paddleRRect, _paddlePaint);

    _paddleGlowPaint
      ..color = themeColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3.0);
    canvas.drawRRect(paddleRRect, _paddleGlowPaint);

    // 4. Balls.
    for (final ball in state._balls) {
      _ballPaint
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      canvas.drawCircle(Offset(ball.x, ball.y), ball.radius, _ballPaint);

      _ballGlowPaint
        ..color = themeColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4.0);
      canvas.drawCircle(Offset(ball.x, ball.y), ball.radius, _ballGlowPaint);
    }

    // 5. Power-ups.
    for (final pu in state._powerups) {
      _powerUpOuterPaint
        ..color = pu.color
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      canvas.drawCircle(Offset(pu.x, pu.y), pu.radius, _powerUpOuterPaint);

      _powerUpInnerPaint
        ..color = const Color(0xFF0A0A1F)
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      canvas.drawCircle(Offset(pu.x, pu.y), pu.radius - 2.0, _powerUpInnerPaint);

      final textSpan = TextSpan(
        style: TextStyle(color: pu.color, fontSize: 8.5, fontWeight: FontWeight.w900),
        text: pu.type == 'multiball'
            ? '3'
            : pu.type == 'expand'
                ? '+'
                : pu.type == 'shield'
                    ? 'S'
                    : pu.type == 'sticky'
                        ? 'K'
                        : 'L',
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      textPainter.paint(canvas, Offset(pu.x - textPainter.width / 2, pu.y - textPainter.height / 2));
    }

    // 6. Lasers.
    for (final laser in state._lasers) {
      _laserPaint
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);
      if (state._verticalMode) {
        canvas.drawRect(Rect.fromLTWH(laser.x, laser.y - laser.width / 2, laser.height, laser.width), _laserPaint);
      } else {
        canvas.drawRect(Rect.fromLTWH(laser.x - laser.width / 2, laser.y, laser.width, laser.height), _laserPaint);
      }
    }

    // 7. Particles.
    for (final particle in state._particles) {
      _particlePaint
        ..color = particle.color.withValues(alpha: particle.life)
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      canvas.drawCircle(Offset(particle.x, particle.y), particle.size * particle.life, _particlePaint);
    }

    // 8. Floating scores.
    for (final fs in state._floatingScores) {
      final textSpan = TextSpan(
        style: TextStyle(
          color: Colors.white.withValues(alpha: fs.life),
          fontSize: 7.0,
          fontWeight: FontWeight.bold,
        ),
        text: "+${fs.score}",
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      textPainter.paint(canvas, Offset(fs.x - textPainter.width / 2, fs.y));
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}

/// Lightweight repaint trigger driven by the game-loop ticker.
class GameRepaintNotifier extends ChangeNotifier {
  void repaint() {
    notifyListeners();
  }
}
