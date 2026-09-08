#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;
uniform float uRadius;
uniform float uYaw;
uniform float uPitch;
uniform sampler2D uAtlas;
uniform sampler2D uVisitMask;
uniform sampler2D uLandMask;
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
  vec3 terrain = texture(uAtlas, uv).rgb;
  // Preserve the observed city lights; cool the unlit terrain for a night atlas.
  float tone = dot(terrain, vec3(0.2126, 0.7152, 0.0722));
  float cityLight = smoothstep(0.16, 0.65, tone);
  terrain = mix(terrain * vec3(0.58, 0.70, 0.88) + vec3(0.010, 0.016, 0.030),
      terrain * vec3(1.05, 1.0, 0.90), cityLight);
  float landMask = smoothstep(0.16, 0.84, texture(uLandMask, uv).r);
  // Ocean remains readable even on the shaded side of the globe.
  vec3 ocean = mix(
    vec3(0.022, 0.055, 0.105),
    vec3(0.045, 0.115, 0.205),
    clamp(0.50 + uv.y * 0.58, 0.0, 1.0)
  );
  vec3 surface = mix(ocean, terrain, landMask);
  vec3 sunDirection = normalize(vec3(-0.45, 0.6, 1.0));
  float sun = max(0.0, dot(normal, sunDirection));
  float light = 0.48 + 0.62 * sun;
  float rim = pow(clamp(1.0 - normal.z, 0.0, 1.0), 3.2);

  // A cool terminator keeps the globe dimensional while leaving the route
  // colors readable. No clouds are composited here by design.
  surface *= mix(0.76, 1.0, smoothstep(0.05, 0.72, sun));

  // A restrained ocean glint suggests water without turning the map into a
  // glossy game asset.
  float oceanSpecular = pow(max(0.0, dot(reflect(-sunDirection, normal),
      vec3(0.0, 0.0, 1.0))), 28.0) * (1.0 - landMask);
  surface += vec3(0.04, 0.07, 0.08) * oceanSpecular;

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
  // Emissive lights should not disappear into the directional shadow.
  color += terrain * cityLight * landMask * (1.0 - sun) * 0.35;
  // Thin blue atmosphere, strongest at the limb and on the daylight side.
  color += vec3(0.06, 0.18, 0.52) * rim * (0.30 + sun * 0.65);
  // Only the subpixel silhouette is antialiased; the entire interior is opaque.
  float coverage = clamp((1.0 - sqrt(r2)) * uRadius, 0.0, 1.0);
  fragColor = vec4(color * coverage, coverage);
}
