import 'package:flutter/material.dart';

import '../models.dart';
import '../screen_metrics.dart';
import 'neon_button.dart';

/// Brief "LEVEL N — name" splash shown before play begins.
class LevelIntroView extends StatelessWidget {
  final int levelIndex;
  final LevelData level;

  const LevelIntroView({
    super.key,
    required this.levelIndex,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "LEVEL ${levelIndex + 1}",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: level.themeColor.withValues(alpha: 0.8),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              level.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: level.themeColor,
                letterSpacing: 2,
                shadows: [Shadow(color: level.themeColor, blurRadius: 12)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The in-game heads-up display: level, lives, score, pause button, combo
/// counter, and the contextual launch / laser hints.
class PlayingHud extends StatelessWidget {
  final int levelIndex;
  final Color themeColor;
  final int lives;
  final int score;
  final int comboCount;
  final bool showLaunchHint;
  final bool showLaserHint;

  /// The screen's real geometry. The HUD is the part of the game that lives in
  /// the corners, so it is the part that has to know where the glass stops.
  final ScreenMetrics metrics;

  /// On Apple TV the pause circle is hidden (there is no pointer to tap it);
  /// the Siri Remote Menu / Play-Pause buttons pause instead, and the hints
  /// speak remote language ("PRESS" rather than "TAP").
  final bool isTv;
  final VoidCallback onPause;

  const PlayingHud({
    super.key,
    required this.levelIndex,
    required this.themeColor,
    required this.lives,
    required this.score,
    required this.comboCount,
    required this.showLaunchHint,
    required this.showLaserHint,
    required this.metrics,
    this.isTv = false,
    required this.onPause,
  });

  /// Top edge of the pause circle, and of the stats row below it. Both are
  /// measured from the top of the stage, which is also where the display's
  /// corner starts curving away.
  static const double _pauseTop = 9;
  static const double _rowTop = 14;

  @override
  Widget build(BuildContext context) {
    // How far the corner has eaten into each row's own y. On a 44mm this is
    // under the fixed insets the HUD used to hardcode and nothing moves; on a
    // 49mm Ultra 3 the corner is 47% rounder and the pause circle has to come
    // in ~10pt further, which is exactly the amount it used to hang off by.
    final double pauseInset = metrics.sideInsetFor(
      _pauseTop,
      atLeast: 16,
      clearance: 3,
    );
    final double rowInset = metrics.sideInsetFor(
      _rowTop,
      atLeast: 20,
      clearance: 3,
    );

    return Stack(
      children: [
        Positioned(
          top: _rowTop,
          left: rowInset,
          // Clear the pause circle (18pt wide) as well as the corner.
          right: pauseInset + 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "LVL ${levelIndex + 1}",
                style: TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  color: themeColor,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: List.generate(
                  3,
                  (index) => Icon(
                    Icons.favorite,
                    size: 8.5,
                    color: index < lives
                        ? Colors.pinkAccent
                        : Colors.grey.shade800,
                  ),
                ),
              ),
              Text(
                "PTS: $score",
                style: const TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (!isTv)
          Positioned(
            top: _pauseTop,
            right: pauseInset,
            child: GestureDetector(
              onTap: onPause,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.pause, size: 9, color: Colors.white),
              ),
            ),
          ),
        if (comboCount > 1)
          Positioned(
            top: 25,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                "${comboCount}x COMBO",
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: Colors.yellowAccent.withValues(
                    alpha: (comboCount / 5.0).clamp(0.5, 1.0),
                  ),
                  letterSpacing: 0.5,
                  shadows: const [
                    Shadow(color: Colors.yellowAccent, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        if (showLaunchHint)
          _hint(isTv ? "PRESS TO LAUNCH" : "TAP TO LAUNCH", Colors.pinkAccent),
        if (showLaserHint)
          _hint(
            isTv ? "PRESS TO SHOOT LASERS" : "TAP TO SHOOT LASERS",
            Colors.redAccent,
          ),
      ],
    );
  }

  Widget _hint(String text, Color color) {
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 6.5,
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pause overlay with resume / quit actions.
class PausedView extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onQuit;

  const PausedView({super.key, required this.onResume, required this.onQuit});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "PAUSED",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
                shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 10)],
              ),
            ),
            const SizedBox(height: 16),
            NeonButton(
              label: "RESUME",
              onPressed: onResume,
              accent: Colors.cyanAccent,
              autofocus: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            ),
            const SizedBox(height: 8),
            NeonButton(
              label: "QUIT",
              onPressed: onQuit,
              accent: Colors.redAccent,
              background: const Color(0xFF280F0F),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Game-over screen with the final score and retry / menu actions.
class GameOverView extends StatelessWidget {
  final int score;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  const GameOverView({
    super.key,
    required this.score,
    required this.onRetry,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "GAME OVER",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.redAccent,
            letterSpacing: 2,
            shadows: [Shadow(color: Colors.redAccent, blurRadius: 10)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "SCORE: $score",
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NeonButton(
              label: "TRY AGAIN",
              onPressed: onRetry,
              accent: Colors.redAccent,
              background: const Color(0xFF280F0F),
              autofocus: true,
              fontSize: 9,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              radius: 15,
            ),
            const SizedBox(width: 8),
            NeonButton(
              label: "MENU",
              onPressed: onMenu,
              accent: Colors.white54,
              background: const Color(0xFF1F1F1F),
              fontSize: 9,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              radius: 15,
            ),
          ],
        ),
      ],
    );
  }
}

/// Level-cleared screen with score, earned stars, and next / menu actions.
class GameWonView extends StatelessWidget {
  final int score;
  final int lives;
  final bool hasNextLevel;
  final VoidCallback onNext;
  final VoidCallback onMenu;

  const GameWonView({
    super.key,
    required this.score,
    required this.lives,
    required this.hasNextLevel,
    required this.onNext,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final stars = lives.clamp(1, 3);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "VICTORY!",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.yellowAccent,
            letterSpacing: 2,
            shadows: [Shadow(color: Colors.yellowAccent, blurRadius: 12)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "SCORE: $score",
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (s) => Icon(
              s < stars ? Icons.star : Icons.star_border,
              size: 14,
              color: s < stars ? Colors.yellowAccent : Colors.grey.shade700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasNextLevel)
              NeonButton(
                label: "NEXT LEVEL",
                onPressed: onNext,
                accent: Colors.yellowAccent,
                background: const Color(0xFF0F280F),
                autofocus: true,
                fontSize: 9,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                radius: 15,
              ),
            const SizedBox(width: 8),
            NeonButton(
              label: "LEVELS",
              onPressed: onMenu,
              accent: Colors.white54,
              background: const Color(0xFF1F1F1F),
              autofocus: !hasNextLevel,
              fontSize: 9,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              radius: 15,
            ),
          ],
        ),
      ],
    );
  }
}
