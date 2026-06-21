import 'package:flutter/material.dart';

import '../models.dart';

/// The title screen: logo, high score, and the Play / orientation buttons.
class MenuView extends StatelessWidget {
  final int highScore;
  final bool verticalMode;
  final VoidCallback onPlay;
  final VoidCallback onToggleMode;

  const MenuView({
    super.key,
    required this.highScore,
    required this.verticalMode,
    required this.onPlay,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "CROWN",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.pinkAccent,
            letterSpacing: 2,
            shadows: [Shadow(color: Colors.pinkAccent, blurRadius: 10)],
          ),
        ),
        const Text(
          "BREAKER",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.cyanAccent,
            letterSpacing: 2,
            shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 10)],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "HIGH SCORE: $highScore",
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400, letterSpacing: 1),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: onPlay,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF101035),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                ),
              ),
              child: const Text(
                "PLAY",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onToggleMode,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.pinkAccent,
                side: const BorderSide(color: Colors.pinkAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                verticalMode ? "VERT" : "HORIZ",
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The level-select grid. Locked levels are greyed out; cleared levels show
/// their earned star rating.
class LevelSelectView extends StatelessWidget {
  final List<LevelData> levels;
  final int maxUnlockedLevel;
  final Map<int, int> levelStars;
  final void Function(int index) onSelect;
  final VoidCallback onBack;

  const LevelSelectView({
    super.key,
    required this.levels,
    required this.maxUnlockedLevel,
    required this.levelStars,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      child: Column(
        children: [
          const Text(
            "SELECT LEVEL",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              itemCount: levels.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1.3,
              ),
              itemBuilder: (context, index) {
                final lvl = levels[index];
                final isLocked = index > maxUnlockedLevel;
                final stars = levelStars[index] ?? 0;
                return InkWell(
                  onTap: isLocked ? null : () => onSelect(index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isLocked ? const Color(0xFF080810) : const Color(0xFF0F0F28),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isLocked ? Colors.grey.shade800 : lvl.themeColor,
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isLocked)
                          Icon(Icons.lock, size: 12, color: Colors.grey.shade700)
                        else
                          Text(
                            "${index + 1}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: lvl.themeColor,
                            ),
                          ),
                        if (!isLocked && levelStars.containsKey(index))
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (s) => Icon(
                                s < stars ? Icons.star : Icons.star_border,
                                size: 7,
                                color: s < stars ? Colors.yellowAccent : Colors.grey.shade800,
                              ),
                            ),
                          )
                        else
                          Text(
                            isLocked ? "LOCKED" : lvl.name.split(" ").first,
                            style: TextStyle(
                              fontSize: 6,
                              color: isLocked ? Colors.grey.shade700 : Colors.white70,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 14, color: Colors.grey),
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}
