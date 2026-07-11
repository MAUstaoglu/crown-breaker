import 'package:flutter/material.dart';

import '../constants.dart';
import '../models.dart';
import 'neon_button.dart';

/// The title screen: logo, high score, and the Play / orientation buttons.
class MenuView extends StatelessWidget {
  final int highScore;
  final bool verticalMode;
  final bool showModeToggle;
  final VoidCallback onPlay;
  final VoidCallback onToggleMode;

  const MenuView({
    super.key,
    required this.highScore,
    required this.verticalMode,
    this.showModeToggle = true,
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
            NeonButton(
              label: "PLAY",
              onPressed: onPlay,
              accent: Colors.cyanAccent,
              autofocus: true,
            ),
            if (showModeToggle) ...[
              const SizedBox(width: 6),
              NeonButton(
                label: verticalMode ? "VERT" : "HORIZ",
                onPressed: onToggleMode,
                accent: Colors.pinkAccent,
                background: const Color(0xFF1A0A14),
                fontSize: 9,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The level-select grid. Locked levels are greyed out; cleared levels show
/// their earned star rating. Tiles glow when focused (tvOS remote).
class LevelSelectView extends StatelessWidget {
  final List<LevelData> levels;
  final int maxUnlockedLevel;
  final Map<int, int> levelStars;
  final void Function(int index) onSelect;
  final VoidCallback onBack;
  final ScrollController? controller;

  /// Whether to show the on-screen back button. Hidden on tvOS, where there is
  /// no pointer to tap it and the Siri Remote Menu button steps back instead.
  final bool showBackButton;

  const LevelSelectView({
    super.key,
    required this.levels,
    required this.maxUnlockedLevel,
    required this.levelStars,
    required this.onSelect,
    required this.onBack,
    this.controller,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final int autofocusIndex =
        kUnlockAllLevels ? 0 : maxUnlockedLevel.clamp(0, levels.length - 1);
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
              controller: controller,
              itemCount: levels.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1.3,
              ),
              itemBuilder: (context, index) {
                final lvl = levels[index];
                final isLocked = !kUnlockAllLevels && index > maxUnlockedLevel;
                return _LevelTile(
                  index: index,
                  level: lvl,
                  isLocked: isLocked,
                  stars: levelStars[index] ?? 0,
                  hasStars: levelStars.containsKey(index),
                  autofocus: index == autofocusIndex,
                  onSelect: isLocked ? null : () => onSelect(index),
                );
              },
            ),
          ),
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 14, color: Colors.grey),
              onPressed: onBack,
            ),
        ],
      ),
    );
  }
}

/// One level cell. Border and fill brighten while focused so the Siri Remote
/// cursor position is obvious; locked tiles are skipped by focus traversal.
class _LevelTile extends StatefulWidget {
  final int index;
  final LevelData level;
  final bool isLocked;
  final int stars;
  final bool hasStars;
  final bool autofocus;
  final VoidCallback? onSelect;

  const _LevelTile({
    required this.index,
    required this.level,
    required this.isLocked,
    required this.stars,
    required this.hasStars,
    required this.autofocus,
    required this.onSelect,
  });

  @override
  State<_LevelTile> createState() => _LevelTileState();
}

class _LevelTileState extends State<_LevelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lvl = widget.level;
    final isLocked = widget.isLocked;
    return InkWell(
      onTap: widget.onSelect,
      autofocus: widget.autofocus && !isLocked,
      canRequestFocus: !isLocked,
      onFocusChange: (f) {
        setState(() => _focused = f);
        // Keep the focused tile on screen. Without this the lazy grid can
        // scroll the Siri Remote's target out of view (and then dispose it,
        // dropping focus entirely). Aligned to leave a margin above/below.
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      },
      focusColor: Colors.transparent, // The border/glow below is the cue.
      child: Container(
        decoration: BoxDecoration(
          color: isLocked
              ? const Color(0xFF080810)
              : _focused
                  ? Color.lerp(const Color(0xFF0F0F28), lvl.themeColor, 0.22)
                  : const Color(0xFF0F0F28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isLocked ? Colors.grey.shade800 : lvl.themeColor,
            width: _focused ? 2.4 : 1.2,
          ),
          boxShadow: _focused
              ? [BoxShadow(color: lvl.themeColor.withValues(alpha: 0.55), blurRadius: 8)]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLocked)
              Icon(Icons.lock, size: 12, color: Colors.grey.shade700)
            else
              Text(
                "${widget.index + 1}",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: lvl.themeColor,
                ),
              ),
            if (!isLocked && widget.hasStars)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (s) => Icon(
                    s < widget.stars ? Icons.star : Icons.star_border,
                    size: 7,
                    color: s < widget.stars ? Colors.yellowAccent : Colors.grey.shade800,
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
  }
}
