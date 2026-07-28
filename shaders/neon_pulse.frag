#version 460 core

// The playfield border as an energy field.
//
// Every flash on this ring corresponds to something that actually happened:
// the ball striking a wall, or a brick breaking. Nothing free-runs. The hue
// and the breathing rate carry the game's tension — lives lost, and how close
// the ball is to the edge you lose on.
//
// Painted as a *stroked* rounded rect, so only the ring's pixels are ever
// shaded — a few thousand on the watch instead of the whole screen. That is
// the difference between an effect that fits the frame budget and one that
// does not (see doc/shaders.md in the flutter-watchos repo).

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;    // 0, 1   — pixel size of the painted area
uniform float uTime;   // 2      — seconds since mount
uniform vec3 uAccent;  // 3,4,5  — the world's neon hue
uniform float uDanger; // 6      — 0 at full lives, 1 on the last one
uniform float uThreat; // 7      — 0..1, ball closing on the losing edge
uniform vec4 uFlareP;  // 8..11  — perimeter positions of up to four impacts
uniform vec4 uFlareI;  // 12..15 — their intensities, decaying to 0

out vec4 fragColor;

const float TAU = 6.28318530718;

// A localised burst centred on `pos`, wrapping around the seam at 0/1.
float flare(float a, float pos, float intensity) {
  if (intensity <= 0.0) return 0.0;
  float d = abs(a - pos);
  d = min(d, 1.0 - d);
  // Tighter as it fades, so a burst collapses to a point rather than dimming.
  float width = 0.03 + 0.09 * intensity;
  return smoothstep(width, 0.0, d) * intensity;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv - 0.5;
  p.x *= uSize.x / uSize.y;

  // Position around the perimeter, 0..1.
  float a = fract(atan(p.y, p.x) / TAU + 1.0);

  // The last life turns the field red. Deliberately a late, sharp switch
  // rather than a linear ramp: half-mixing a cyan world toward red lands on
  // a washed-out grey, which reads as "the shader broke", not as danger.
  vec3 accent = mix(uAccent, vec3(1.0, 0.18, 0.24), smoothstep(0.45, 1.0, uDanger));

  // Chunky travelling segments — about ten around the perimeter. Obvious
  // per-pixel structure at any distance, and the part that could not be done
  // with a gradient.
  float bands = 0.75 + 0.25 * sin(a * 60.0 - uTime * 6.0);

  // The field breathes faster as the situation gets worse: lives gone, or a
  // ball bearing down on the edge behind the paddle.
  float urgency = max(uDanger, uThreat);
  float breathe = 0.85 + 0.15 * sin(uTime * (2.2 + 6.0 * urgency));

  float glow = 1.15 * bands * breathe;

  // Impacts. Each one is a real collision the player just caused.
  glow += 3.2 * flare(a, uFlareP.x, uFlareI.x);
  glow += 3.2 * flare(a, uFlareP.y, uFlareI.y);
  glow += 3.2 * flare(a, uFlareP.z, uFlareI.z);
  glow += 3.2 * flare(a, uFlareP.w, uFlareI.w);

  // Push the peaks to white so impacts bloom on a projector.
  vec3 col = accent * glow + vec3(max(0.0, glow - 1.2) * 0.7);

  // Flutter expects premultiplied alpha.
  float alpha = clamp(glow * 0.9, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0) * alpha, alpha);
}
