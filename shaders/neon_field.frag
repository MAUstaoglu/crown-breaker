#version 460 core

// Animated neon field behind the playfield, tinted to the current world's hue.
//
// Deliberately cheap: two sines, one length, no loops, no noise lookups. The
// watchOS engine rasterises this per pixel on the CPU, so every extra
// instruction is paid 190k times a frame on a 45mm watch — and 2M times on a
// 1080p Apple TV. See doc/shaders.md in the flutter-watchos repo.

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;    // 0, 1 — pixel size of the painted rect
uniform float uTime;   // 2    — seconds since the widget mounted
uniform vec3 uBase;    // 3, 4, 5 — the world's near-black background
uniform vec3 uAccent;  // 6, 7, 8 — the world's neon hue
uniform float uEnergy; // 9    — 0 in menus, 1 during play

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // Centre and correct for aspect so the field does not stretch on the TV.
  vec2 p = uv - 0.5;
  p.x *= uSize.x / uSize.y;

  float t = uTime * 0.25;

  // Two drifting diagonal waves crossing each other, folded to 0..1.
  float w = sin((p.x + p.y) * 5.0 + t * 2.0)
          + sin((p.x - p.y) * 7.0 - t * 1.4);
  float field = 0.5 + 0.25 * w;

  // Falloff pushes the energy to the edges, keeping the middle of the
  // playfield dark so bricks, ball, and HUD stay readable on top.
  float edge = smoothstep(0.15, 0.75, length(p));

  // ADD the neon onto the base rather than modulating it — the world
  // backgrounds are near-black, so anything multiplicative disappears.
  vec3 col = uBase + uAccent * field * edge * (0.10 + 0.22 * uEnergy);

  fragColor = vec4(col, 1.0);
}
