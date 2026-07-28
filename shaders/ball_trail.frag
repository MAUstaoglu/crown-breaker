#version 460 core

// A comet trail streaming off the ball.
//
// Painted as a stroked line running backwards along the ball's velocity, so
// only the trail's own pixels are shaded — the same budget trick as
// neon_pulse.frag. Intensity falls off with distance from the ball, so the
// head is white-hot and the tail dissolves.

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform float uTime;   // 0    — seconds, streams the energy segments
uniform vec3 uAccent;  // 1, 2, 3 — the world's neon hue
uniform vec2 uHead;    // 4, 5 — ball centre, in the same space as gl_FragCoord
uniform float uLen;    // 6    — trail length in pixels

out vec4 fragColor;

void main() {
  float d = distance(FlutterFragCoord().xy, uHead);

  // Quadratic falloff: hot at the ball, gone by the end of the stroke.
  float fade = 1.0 - clamp(d / uLen, 0.0, 1.0);
  fade *= fade;

  // Segments streaming down the tail — the part a plain gradient cannot do.
  float bands = 0.70 + 0.30 * sin(d * 0.9 - uTime * 18.0);

  float glow = fade * bands * 2.0;

  // White-hot core where the trail meets the ball.
  vec3 col = uAccent * glow + vec3(max(0.0, glow - 1.0) * 0.8);

  // Flutter expects premultiplied alpha.
  float alpha = clamp(glow, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0) * alpha, alpha);
}
