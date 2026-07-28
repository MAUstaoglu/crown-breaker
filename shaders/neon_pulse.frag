#version 460 core

// The playfield border as an energy field.
//
// Every flash on this ring corresponds to something that actually happened:
// the ball striking a wall, or a brick breaking. Nothing free-runs.
//
// The ring is not uniform. Three sides are solid wall the ball bounces off;
// the fourth is the gap the paddle guards, and losing the ball through it
// costs a life. That edge is drawn in a warm hue with its own hazard pattern
// so the asymmetry is visible at a glance — the border teaches the rules.
// Brightness and breathing rate carry the tension on top of that: lives lost,
// and how close the ball is to that open edge.
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
uniform vec2 uPerilDir; // 16,17 — picks the edge that costs a life: (0,1) for
                        //         the paddle at the bottom, (1,0) in vertical
                        //         mode where it guards the right-hand side

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

  // How much this pixel belongs to the edge that costs a life. The dot picks
  // out uv.y or uv.x, so one expression covers both paddle orientations. The
  // ramp is deliberately wide: it climbs the two side rails toward the open
  // edge instead of stopping dead at the corners, so the border reads as a
  // gradient into danger rather than as three walls and a stripe.
  float peril = smoothstep(0.62, 0.90, dot(uv, uPerilDir));

  // Lives gone, or a ball bearing down on the open edge.
  float urgency = max(uDanger, uThreat);

  // Hue is reserved for one question: which edge can kill you. The three solid
  // rails keep the world's accent no matter how bad things get, and only the
  // open edge runs warm — amber at rest, red as the situation deteriorates.
  // The whole ring used to turn red on the last life, which is exactly when
  // this distinction matters most; that cue now lives in brightness and rate
  // so it cannot swallow the warning colour.
  vec3 hot = mix(vec3(1.0, 0.55, 0.12), vec3(1.0, 0.12, 0.16), urgency);
  vec3 accent = mix(uAccent, hot, peril);

  // Chunky travelling segments — about ten around the perimeter. Obvious
  // per-pixel structure at any distance, and the part that could not be done
  // with a gradient.
  float bands = 0.75 + 0.25 * sin(a * 60.0 - uTime * 6.0);

  // The open edge gets its own pattern: tighter, near-square hazard bars that
  // run faster under pressure. Structure as well as hue, so the edge is still
  // marked for a colour-blind player or a washed-out projector.
  float hazard = smoothstep(
      0.35, 0.65, 0.5 + 0.5 * sin(a * 110.0 - uTime * (7.0 + 12.0 * urgency)));
  float pattern = mix(bands, 0.55 + 0.75 * hazard, peril);

  float breathe = 0.85 + 0.15 * sin(uTime * (2.2 + 6.0 * urgency));

  float glow = 1.15 * pattern * breathe;

  // The open edge always burns hotter than the rails, and flares up further as
  // a ball commits to it.
  glow *= 1.0 + peril * (0.35 + 1.5 * urgency);

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
