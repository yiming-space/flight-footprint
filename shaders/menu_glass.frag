#version 320 es
#include <flutter/runtime_effect.glsl>

// ImageFilter.shader supplies the input texture size and sampler.
uniform vec2 u_size;
uniform sampler2D u_texture_input;
uniform float u_refraction_enabled;
uniform vec4 u_bar_rect_px;
uniform float u_device_pixel_ratio;
uniform float u_corner_radius_px;
uniform float u_edge_scale;
uniform float u_highlight_gain;
uniform float u_adaptive_contrast;
uniform float u_local_coordinates;
out vec4 frag_color;

float capsule_sdf(vec2 point, vec2 half_size, float radius) {
  vec2 q = abs(point) - vec2(half_size.x - radius, half_size.y - radius);
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

vec4 sample_texture(vec2 physical_px) {
  // Keep this unflipped: the GLES composition path with native blur was
  // verified in the probe. This shader must remain the outer compose filter.
  vec2 uv = clamp(physical_px / u_size, vec2(0.0), vec2(1.0));
  return texture(u_texture_input, uv);
}

void main() {
  vec2 physical_px = FlutterFragCoord().xy;
  vec4 original = sample_texture(physical_px);
  if (u_refraction_enabled < 0.5) {
    frag_color = original;
    return;
  }

  vec2 panel_size = u_local_coordinates > 0.5 ? u_size : u_bar_rect_px.zw;
  vec2 half_size = panel_size * 0.5;
  // Image-filter coordinates belong to the bound input texture. Using the
  // window-space card dimensions here can put most of that texture outside
  // the SDF, incorrectly shading the whole face as a reflective bevel.
  vec2 rect_origin = u_local_coordinates > 0.5
      ? vec2(0.0)
      : u_bar_rect_px.xy;
  vec2 local = physical_px - rect_origin - half_size;
  // Controls still pass half their height, preserving the original lens.
  // Large cards pass their actual corner radius instead of a vertical capsule.
  float radius = u_corner_radius_px;
  float sdf = capsule_sdf(local, half_size, radius);
  float rim_width = 6.5 * u_device_pixel_ratio * u_edge_scale;
  float rim = 1.0 - smoothstep(0.0, rim_width, max(-sdf, 0.0));

  vec2 gradient = vec2(
    capsule_sdf(local + vec2(1.0, 0.0), half_size, radius) -
        capsule_sdf(local - vec2(1.0, 0.0), half_size, radius),
    capsule_sdf(local + vec2(0.0, 1.0), half_size, radius) -
        capsule_sdf(local - vec2(0.0, 1.0), half_size, radius)
  );
  vec2 normal = gradient / max(length(gradient), 0.0001);
  float displacement =
      5.0 * u_device_pixel_ratio * u_edge_scale * clamp(rim, 0.0, 1.0);

  // Pull the edge sample inward. The center has zero displacement, preserving
  // the native blurred image there while bending only the glass rim.
  frag_color = sample_texture(physical_px - normal * displacement);
  if (u_edge_scale > 1.0) {
    // A continuous rounded bevel, with no inset line or projected shadow.
    // The default control path above is unchanged when edge scale is one.
    float facing = dot(normal, normalize(vec2(-0.6, -0.8)));
    float bevel = pow(clamp(rim, 0.0, 1.0), 1.3);
    // Read the real blurred backdrop per pixel, so the same glass responds
    // continuously as cards, map colors and page washes pass beneath it.
    vec3 backdrop_color = original.a > 0.0001
        ? original.rgb / original.a : vec3(0.0);
    float background_light = clamp(
        dot(backdrop_color, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    // Native blur already smooths small text/detail. Adapt continuously to
    // that luminance without CPU readback, thresholds or an animation ticker.
    float bright_backdrop = smoothstep(0.72, 0.97, background_light)
        * u_adaptive_contrast;
    float light_response = mix(0.52, 0.26, background_light);
    float shade_response = mix(0.035, 0.13, background_light)
        + 0.075 * bright_backdrop;
    float highlight =
        light_response * max(facing, 0.0) * bevel;
    highlight *= u_highlight_gain;
    float turning_away = shade_response * max(-facing, 0.0) * bevel;
    // Use nearby interface colors as a soft local environment reflection.
    // Sampling the already blurred backdrop prevents sharp duplicate content.
    vec2 tangent = vec2(-normal.y, normal.x);
    vec2 rect_min = rect_origin;
    vec2 rect_max = rect_min + panel_size;
    // Sample the already-blurred backdrop from inside the glass bounds. An
    // outward sample can leave the filter layer and introduce transparent
    // black wedges at the corners.
    vec2 environment_point = clamp(
        physical_px - normal * 12.0 * u_device_pixel_ratio,
        rect_min,
        rect_max);
    vec2 tangent_point = clamp(
        environment_point + tangent * 16.0 * u_device_pixel_ratio,
        rect_min,
        rect_max);
    vec4 environment_sample = mix(
        sample_texture(environment_point),
        sample_texture(tangent_point),
        0.35);
    float alpha = frag_color.a;
    vec3 glass_color = alpha > 0.0001
        ? frag_color.rgb / alpha
        : vec3(0.0);
    float environment_alpha = environment_sample.a;
    vec3 environment = environment_alpha > 0.0001
        ? environment_sample.rgb / environment_alpha
        : vec3(0.0);
    vec3 reflection_tint = mix(vec3(1.0), environment, 0.42);
    glass_color = mix(glass_color, environment,
        0.20 * bevel * u_highlight_gain);
    glass_color = mix(glass_color, reflection_tint, highlight);
    // A faint neutral absorption distinguishes glass laid over white cards.
    // It fades out over darker/colorful content; foreground icons stay sharp.
    glass_color *= 1.0 - 0.05 * bright_backdrop;
    glass_color *= 1.0 - turning_away;
    frag_color.rgb = glass_color * alpha;
  }
}
