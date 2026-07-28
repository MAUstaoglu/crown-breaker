#version 460 core

// A pulse of energy racing around the playfield border.
//
// Painted as a *stroked* rounded rect, so only the ring's pixels are ever
// shaded — a few thousand on the watch instead of the whole screen. That is
// the difference between an effect that fits the frame budget and one that
// does not (see doc/shaders.md in the flutter-watchos repo).
//
// Tuned to read from the back of an auditorium: a sharp comet head, chunky
// energy segments, and a hard white bloom at the peaks.

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;    // 0, 1 — pixel size of the painted area
uniform float uTime;   // 2    — seconds since mount
uniform vec3 uAccent;  // 3, 4, 5 — the world's neon hue
uniform float uImpact; // 6    — 0..1, spikes when the game shakes

out vec4 fragColor;

const float TAU = 6.28318530718;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv - 0.5;
  p.x *= uSize.x / uSize.y;

  // Position around the perimeter, 0..1.
  float a = fract(atan(p.y, p.x) / TAU + 1.0);

  // Comet head racing around the border — faster while the screen shakes.
  float head = fract(a - uTime * (0.30 + 0.50 * uImpact));
  float comet = smoothstep(0.30, 0.0, head);
  comet *= comet; // tighten to a sharp head with a long tail

  // Chunky travelling segments — about ten around the perimeter. Obvious
  // per-pixel structure at any distance, and the part that could not be done
  // with a gradient.
  float bands = 0.75 + 0.25 * sin(a * 60.0 - uTime * 6.0);

  // Slow breathing. Kept near the top of its range so the whole ring stays
  // lit — a dim base reads as nothing from the back of a room.
  float breathe = 0.85 + 0.15 * sin(uTime * 2.2);

  float glow = 1.25 * bands * breathe + 2.5 * comet + 1.8 * uImpact;

  // Push the peaks to white so they bloom on a projector.
  vec3 col = uAccent * glow + vec3(max(0.0, glow - 1.2) * 0.7);

  // Flutter expects premultiplied alpha.
  float alpha = clamp(glow * 0.9, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0) * alpha, alpha);
}
