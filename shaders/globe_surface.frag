#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;
uniform float uRadius;
uniform vec2 uYawRotation;
uniform vec2 uPitchRotation;
uniform vec3 uSunDirection;
// The night and day atlases are packed vertically into one texture. Keeping
// one color sampler avoids sampler binding differences across Android GPUs.
uniform sampler2D uAtlas;
uniform sampler2D uLandMask;
out vec4 fragColor;

void main() {
  vec2 p = (FlutterFragCoord().xy - uCenter) / uRadius;
  float r2 = dot(p, p);
  if (r2 > 1.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Inverse orthographic projection. The transformed vector is in the same
  // geographic frame as the solar vector calculated on the Dart side.
  vec3 normal = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r2)));
  float y = normal.y * uPitchRotation.x + normal.z * uPitchRotation.y;
  float z = -normal.y * uPitchRotation.y + normal.z * uPitchRotation.x;
  float x = normal.x * uYawRotation.x - z * uYawRotation.y;
  z = normal.x * uYawRotation.y + z * uYawRotation.x;
  vec3 worldNormal = normalize(vec3(x, y, z));

  const float pi = 3.141592653589793;
  vec2 uv = vec2(
    fract(atan(worldNormal.x, worldNormal.z) / (2.0 * pi) + 0.5),
    clamp(0.5 - asin(clamp(worldNormal.y, -1.0, 1.0)) / pi, 0.00025, 0.99975)
  );

  vec3 nightTexture = texture(uAtlas, vec2(uv.x, uv.y * 0.5)).rgb;
  vec3 dayTexture = texture(uAtlas, vec2(uv.x, 0.5 + uv.y * 0.5)).rgb;
  float landMask = smoothstep(0.16, 0.84, texture(uLandMask, uv).r);
  vec3 sunDirection = normalize(uSunDirection);
  float solar = dot(worldNormal, sunDirection);
  // A deliberately broad twilight band keeps the terminator soft instead of
  // making the atlas swap read like a hard circular cutout.
  float daylight = smoothstep(-0.38, 0.38, solar);
  float sun = max(0.0, solar);

  // The day atlas supplies realistic relief and earth tones. Its ocean is
  // intentionally ignored because the mask lets us keep a deeper, cleaner
  // blue ocean that reads well beneath routes and markers.
  vec3 dayLand = dayTexture * vec3(0.87, 0.95, 0.92) + vec3(0.009, 0.013, 0.015);
  // Keep the full Black Marble distribution: its city lights remain visible
  // on the night side without adding a separate synthetic orange layer.
  float nightLuma = dot(nightTexture, vec3(0.30, 0.59, 0.11));
  vec3 coolNightTexture = mix(vec3(nightLuma), nightTexture, 0.45);
  vec3 nightLand = coolNightTexture * vec3(0.82, 0.88, 1.00) + vec3(0.003, 0.005, 0.009);
  vec3 dayOcean = mix(
    vec3(0.044, 0.176, 0.300),
    vec3(0.108, 0.330, 0.500),
    clamp(0.50 + uv.y * 0.58, 0.0, 1.0)
  );
  vec3 nightOcean = mix(
    vec3(0.012, 0.032, 0.056),
    vec3(0.030, 0.082, 0.132),
    clamp(0.50 + uv.y * 0.58, 0.0, 1.0)
  );
  vec3 daySurface = mix(dayOcean, dayLand, landMask);
  vec3 nightSurface = mix(nightOcean, nightLand, landMask);
  float dayShade = 0.64 + 0.36 * smoothstep(-0.08, 0.76, solar);
  vec3 surface = mix(nightSurface, daySurface * dayShade, daylight);

  vec3 color = surface;

  // The atmosphere belongs to the screen-facing silhouette, not a fixed
  // geographic longitude. Using the pre-rotation view normal prevents a
  // false blue stripe from appearing inside the ocean as the globe turns.
  float rimEdge = clamp(1.0 - normal.z, 0.0, 1.0);
  float rim = smoothstep(0.06, 0.98, rimEdge);
  rim *= rim;
  color += vec3(0.20, 0.48, 0.78) * rim * (0.035 + sun * 0.12);

  // Only the subpixel silhouette is antialiased; the entire interior is opaque.
  float coverage = clamp((1.0 - sqrt(r2)) * uRadius, 0.0, 1.0);
  fragColor = vec4(color * coverage, coverage);
}
