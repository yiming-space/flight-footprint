#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;
uniform float uRadius;
uniform float uYaw;
uniform float uPitch;
uniform sampler2D uAtlas;
uniform sampler2D uVisitMask;
out vec4 fragColor;

void main() {
  vec2 p = (FlutterFragCoord().xy - uCenter) / uRadius;
  float r2 = dot(p, p);
  if (r2 > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  // Inverse orthographic projection: every fragment has exactly one visible
  // surface location. No clipped polygon is closed across the globe's face.
  vec3 normal = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r2)));
  float y = normal.y * cos(uPitch) + normal.z * sin(uPitch);
  float z = -normal.y * sin(uPitch) + normal.z * cos(uPitch);
  float x = normal.x * cos(uYaw) - z * sin(uYaw);
  z = normal.x * sin(uYaw) + z * cos(uYaw);
  const float pi = 3.141592653589793;
  vec2 uv = vec2(fract(atan(x, z) / (2.0 * pi) + 0.5),
                 clamp(0.5 - asin(clamp(y, -1.0, 1.0)) / pi, 0.00025, 0.99975));
  vec3 surface = texture(uAtlas, uv).rgb;
  float light = 0.55 + 0.53 * max(0.0, dot(normal, normalize(vec3(-0.45, 0.6, 1.0))));
  float rim = pow(1.0 - normal.z, 4.0);
  // The atlas uses a lifted blue-slate ocean so the globe remains distinct
  // from the near-black fullscreen background. The mist-blue footprint fill is
  // the same role and tone used by the flat map.
  float visited = texture(uVisitMask, uv).a;
  vec3 footprint = vec3(0.471, 0.698, 0.784);
  // The mask is a solid visited-country fill, not a radial point glow.
  float footprintMask = smoothstep(0.25, 0.75, visited);
  float footprintMix = footprintMask * 0.40;
  vec3 color = mix(
    surface * light,
    footprint * (0.88 + light * 0.28),
    footprintMix
  );
  color += vec3(0.025, 0.075, 0.16) * rim * 0.28;
  // Only the subpixel silhouette is antialiased; the entire interior is opaque.
  float coverage = clamp((1.0 - sqrt(r2)) * uRadius, 0.0, 1.0);
  fragColor = vec4(color * coverage, coverage);
}
