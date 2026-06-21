import 'package:flutter/material.dart';

import '../models.dart';

/// Brief "LEVEL N — name" splash shown before play begins.
class LevelIntroView extends StatelessWidget {
  final int levelIndex;
  final LevelData level;

  const LevelIntroView({super.key, required this.levelIndex, required this.level});

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
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 14,
          left: 20,
          right: 38,
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
                    color: index < lives ? Colors.pinkAccent : Colors.grey.shade800,
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
        Positioned(
          top: 13,
          right: 20,
          child: InkWell(
            onTap: onPause,
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.pause, size: 8, color: Colors.white38),
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
                  color: Colors.yellowAccent.withValues(alpha: (comboCount / 5.0).clamp(0.5, 1.0)),
                  letterSpacing: 0.5,
                  shadows: const [Shadow(color: Colors.yellowAccent, blurRadius: 6)],
                ),
              ),
            ),
          ),
        if (showLaunchHint) _hint("TAP TO LAUNCH", Colors.pinkAccent),
        if (showLaserHint) _hint("TAP TO SHOOT LASERS", Colors.redAccent),
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
            ElevatedButton(
              onPressed: onResume,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF101035),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.cyanAccent, width: 1.2),
                ),
              ),
              child: const Text(
                "RESUME",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onQuit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF280F0F),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.redAccent, width: 1.0),
                ),
              ),
              child: const Text(
                "QUIT",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
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
        Text("SCORE: $score", style: const TextStyle(fontSize: 12, color: Colors.white)),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF280F0F),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
              child: const Text("TRY AGAIN", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onMenu,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F1F1F),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("MENU", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
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
        Text("SCORE: $score", style: const TextStyle(fontSize: 12, color: Colors.white)),
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
              ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F280F),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.yellowAccent),
                  ),
                ),
                child: const Text("NEXT LEVEL", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onMenu,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F1F1F),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("LEVELS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }
}
