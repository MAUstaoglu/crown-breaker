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
//
// Everything that varies per *frame* rather than per *pixel* is computed in
// Dart and arrives as a uniform. On a watch this runs on the CPU once per
// shaded pixel, so a `sin` of a uniform means thousands of identical
// transcendentals per frame where the painter would spend one. That is why
// uDanger/uThreat/uTime are absent: what the shader needs from them are the
// derived values below.

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;         // 0, 1   — pixel size of the painted area
uniform float uBandPhase;   // 2      — travelling-band phase (time * rate)
uniform vec3 uAccent;       // 3,4,5  — the world's neon hue
uniform float uBreathe;     // 6      — precomputed breathing multiplier
uniform float uPerilBoost;  // 7      — extra glow on the losing edge
uniform vec4 uFlareP;       // 8..11  — perimeter positions of up to four impacts
uniform vec4 uFlareI;       // 12..15 — their intensities, decaying to 0
uniform vec2 uPerilDir;     // 16,17  — picks the edge that costs a life: (0,1)
                            //          for the paddle at the bottom, (1,0) in
                            //          vertical mode where it guards the right
uniform vec3 uHot;          // 18,19,20 — the losing edge's hue for this frame
uniform float uHazardPhase; // 21     — hazard-bar phase (time * rate)
uniform float uGuardFrac;   // 22     — how far in from each end of the losing
                            //          edge the paddle can actually travel, as
                            //          a fraction of that edge's run

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
  // out uv.y or uv.x, so one expression covers both paddle orientations.
  float peril = smoothstep(0.62, 0.90, dot(uv, uPerilDir));

  // ...but only across the stretch the paddle can actually reach. The marking
  // answers "where do you have to be", so it has to agree with where the paddle
  // is allowed to go — no shorter, or it stops before the paddle does and the
  // last stretch of travel looks safe; no longer, or it points at ends the
  // player cannot cover. Swapping uPerilDir's components gives the coordinate
  // that runs *along* the losing edge rather than across it, so this stays one
  // expression for both orientations.
  //
  // It is full strength exactly at the paddle's limit and tapers out over the
  // short run past it, which is why the band laps a little onto the corner
  // curve — so does the paddle.
  float along = dot(uv, vec2(uPerilDir.y, uPerilDir.x));
  float fromEnd = min(along, 1.0 - along);
  peril *= smoothstep(uGuardFrac * 0.55, uGuardFrac, fromEnd);

  // Hue is reserved for one question: which edge can kill you. The three solid
  // rails keep the world's accent no matter how bad things get, and only the
  // open edge runs warm — amber at rest, red as the situation deteriorates.
  vec3 accent = mix(uAccent, uHot, peril);

  // Chunky travelling segments — ten around the perimeter. Obvious per-pixel
  // structure at any distance, and the part that could not be done with a
  // gradient.
  //
  // The count must be a whole number of TAU, because `a` wraps 1 -> 0 at the
  // middle of the right-hand rail and the pattern has to meet itself there. The
  // old `a * 60.0` was 9.55 cycles, so the phase jumped ~198 degrees across the
  // seam and left a hard line down the ring at that one spot.
  float bands = 0.75 + 0.25 * sin(a * TAU * 10.0 - uBandPhase);

  // The open edge gets its own pattern: tighter, near-square hazard bars that
  // run faster under pressure. Structure as well as hue, so the edge is still
  // marked for a colour-blind player or a washed-out projector.
  //
  // Eighteen cycles for the same seam reason as the bands above, and because 18
  // is the whole number nearest the 17.5 the old `a * 110.0` worked out to, so
  // the bars keep their pitch.
  float hazard =
      smoothstep(0.35, 0.65, 0.5 + 0.5 * sin(a * TAU * 18.0 - uHazardPhase));
  float pattern = mix(bands, 0.55 + 0.75 * hazard, peril);

  float glow = 1.15 * pattern * uBreathe;

  // The open edge always burns hotter than the rails, and flares up further as
  // a ball commits to it.
  glow *= 1.0 + peril * uPerilBoost;

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
