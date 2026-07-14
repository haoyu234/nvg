@module glyph

@block load_transform
mat3 loadTransform(int idx) {
  return mat3(vec3(transforms[idx].t1, 0.0),
        vec3(transforms[idx].t2, 0.0),
        vec3(transforms[idx].t3, 1.0));
}
@end

@vs vs_glyph
// Same transform scheme as the path vertex stage: affine transform to screen
// pixels, then view_size projection to NDC. transform1/2/3 use the identical
// vec2-row layout as the path fragment stage's paint transform:
//   transform1 = [xx, yx], transform2 = [xy, yy], transform3 = [dx, dy]
// They carry the per-run canvas transform (rotation / scale / translation),
// shared by all glyphs in one draw call.
layout(binding=0) uniform vs_params {
  vec2 view_size;
  int mvp_index;
};

in vec4 vs_draw_rect;        // xy = screen position (pixels), zw = screen size (pixels)
in vec4 vs_text_color;
in vec4 vs_backdrop_color;
in ivec4 vs_glyph_params;    // x = glyph_loc_x, y = glyph_loc_y, z = max_band_x, w = max_band_y, per-instance
in int vs_glyph_transform_index;

out vec2 vs_out_glyph_pos;       // fragment position in glyph space
out vec2 vs_out_pos;       // fragment position in text-local canvas space
out vec4 vs_out_text_color;
out flat ivec4 vs_out_glyph_params;
out flat vec4 vs_out_backdrop_color;

struct transform_item {
  vec2 t1;
  vec2 t2;
  vec2 t3;
};
layout (binding = 1) readonly buffer transform_buf {
  transform_item transforms[];
};

@include_block load_transform

void main() {
  mat3 glyph_transform = loadTransform(vs_glyph_transform_index);
  mat3 mvp = loadTransform(mvp_index);

  vec2 quad_pos = vec2(gl_VertexIndex & 1, (gl_VertexIndex>>1) & 1);
  vec2 local_pos = vs_draw_rect.xy + quad_pos * vs_draw_rect.zw;
  vec2 layer_pos = (glyph_transform * vec3(local_pos, 1.0)).xy;
  vec2 screen_pos = (mvp * vec3(layer_pos, 1.0)).xy;

  vs_out_pos = local_pos;
  vs_out_glyph_pos = quad_pos;
  vs_out_text_color = vs_text_color;
  vs_out_glyph_params = vs_glyph_params;
  vs_out_backdrop_color = vs_backdrop_color;

  float x = 2.0 * screen_pos.x / view_size.x - 1.0;
  float y = 1.0 - 2.0 * screen_pos.y / view_size.y;
  gl_Position = vec4(x, y, 0.0, 1.0);
}
@end

@fs fs_glyph
layout(binding=2) uniform texture2D curve_tex;
layout(binding=3) uniform utexture2D band_tex;

layout(binding=4) uniform sampler point_sampler;
// band_tex is a uint texture; sokol/D3D/WebGPU require its sampler to be
// NON-FILTERING (VALIDATE_SHADERDESC_NONFILTERING_SAMPLER_REQUIRED). The
// meta-tag below makes sokol-shdc emit samplerTypeNonfiltering directly.
@sampler_type band_smp nonfiltering
layout(binding=5) uniform sampler band_smp;

layout (std140, binding = 6) uniform fs_params {
  vec2 extent;
  int paint_transform_index;
  float radius;
  float feather;
  int render_flags;
};

struct transform_item_fs {
  vec2 t1;
  vec2 t2;
  vec2 t3;
};
layout (binding = 7) readonly buffer transform_buf_fs {
  transform_item_fs transforms[];
};

@include_block load_transform

layout (binding = 8) uniform texture2D image_tex;
layout (binding = 9) uniform sampler image_smp;

float sdfRoundRect(vec2 pt, vec2 ext, float rad)
{
  vec2 ext2 = ext - vec2(rad, rad);
  vec2 d = abs(pt) - ext2;
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rad;
}

in vec2 vs_out_glyph_pos;
in vec2 vs_out_pos;
in vec4 vs_out_text_color;
in flat ivec4 vs_out_glyph_params;
in flat vec4 vs_out_backdrop_color;
out vec4 fs_out_color;

ivec2 bandLoc(ivec2 base, int offset) {
  ivec2 pos = ivec2(base.x + offset, base.y);
  pos.y += pos.x >> 12;
  pos.x &= 4095;
  return pos;
}
uint calcRootCode(float y1, float y2, float y3) {
  uint s1 = floatBitsToUint(y1) >> 31u;
  uint s2 = floatBitsToUint(y2) >> 30u;
  uint s3 = floatBitsToUint(y3) >> 29u;
  uint combined = (s2 & 2u) | (s1 & ~2u);
  combined = (s3 & 4u) | (combined & ~4u);
  return (0x2E74u >> combined) & 0x0101u;
}
vec2 solveHoriz(vec4 points_01, vec2 point_2) {
  vec2 a = points_01.xy - points_01.zw * 2.0 + point_2;
  vec2 b = points_01.xy - points_01.zw;
  float inv_a = 1.0 / a.y;
  float half_inv_b = 0.5 / b.y;
  float discriminant = sqrt(max(b.y * b.y - a.y * points_01.y, 0.0));
  float t1 = (b.y - discriminant) * inv_a;
  float t2 = (b.y + discriminant) * inv_a;
  if (abs(a.y) < 1.0 / 65536.0) { t1 = points_01.y * half_inv_b; t2 = t1; }
  return vec2(
    (a.x * t1 - b.x * 2.0) * t1 + points_01.x,
    (a.x * t2 - b.x * 2.0) * t2 + points_01.x
  );
}
vec2 solveVert(vec4 points_01, vec2 point_2) {
  vec2 a = points_01.xy - points_01.zw * 2.0 + point_2;
  vec2 b = points_01.xy - points_01.zw;
  float inv_a = 1.0 / a.x;
  float half_inv_b = 0.5 / b.x;
  float discriminant = sqrt(max(b.x * b.x - a.x * points_01.x, 0.0));
  float t1 = (b.x - discriminant) * inv_a;
  float t2 = (b.x + discriminant) * inv_a;
  if (abs(a.x) < 1.0 / 65536.0) { t1 = points_01.x * half_inv_b; t2 = t1; }
  return vec2(
    (a.y * t1 - b.y * 2.0) * t1 + points_01.y,
    (a.y * t2 - b.y * 2.0) * t2 + points_01.y
  );
}
void main() {
  ivec2 glyph_loc = vs_out_glyph_params.xy;
  int max_band_x = vs_out_glyph_params.z;
  int max_band_y = vs_out_glyph_params.w;
  vec2 glyph_units_per_pixel = 1.0 / fwidth(vs_out_glyph_pos);
  vec2 band_scale = vec2(float(max_band_x) + 1.0, float(max_band_y) + 1.0);
  ivec2 band_index = clamp(
    ivec2(vs_out_glyph_pos * band_scale),
    ivec2(0, 0),
    ivec2(max_band_x, max_band_y)
  );
  // Horizontal bands (ray in +X)
  float h_winding = 0.0;
  float h_edge_weight = 0.0;
  {
    uvec4 band_header = texelFetch(usampler2D(band_tex, band_smp),
                     bandLoc(glyph_loc, band_index.y), 0);
    int curve_count = int(band_header.x);
    ivec2 entry_list_start = bandLoc(glyph_loc, int(band_header.y));
    for (int i = 0; i < curve_count && i < 128; i++) {
      ivec2 entry_coord = bandLoc(entry_list_start, i);
      uvec4 band_entry = texelFetch(usampler2D(band_tex, band_smp), entry_coord, 0);
      ivec2 curve_tex_coord = ivec2(band_entry.x, band_entry.y);
      vec4 points_01 = texelFetch(sampler2D(curve_tex, point_sampler), curve_tex_coord, 0)
              - vec4(vs_out_glyph_pos, vs_out_glyph_pos);
      ivec2 next_tex_coord = bandLoc(curve_tex_coord, 1);
      vec2 point_2 = texelFetch(sampler2D(curve_tex, point_sampler), next_tex_coord, 0).xy
              - vs_out_glyph_pos;
      if (max(max(points_01.x, points_01.z), point_2.x) * glyph_units_per_pixel.x < -0.5) break;
      uint root_mask = calcRootCode(points_01.y, points_01.w, point_2.y);
      if (root_mask != 0u) {
        vec2 crossings = solveHoriz(points_01, point_2) * glyph_units_per_pixel.x;
        if ((root_mask & 1u) != 0u) {
          h_winding += clamp(crossings.x + 0.5, 0.0, 1.0);
          h_edge_weight = max(h_edge_weight, clamp(1.0 - abs(crossings.x) * 2.0, 0.0, 1.0));
        }
        if (root_mask > 1u) {
          h_winding -= clamp(crossings.y + 0.5, 0.0, 1.0);
          h_edge_weight = max(h_edge_weight, clamp(1.0 - abs(crossings.y) * 2.0, 0.0, 1.0));
        }
      }
    }
  }
  // Vertical bands (ray in +Y)
  float v_winding = 0.0;
  float v_edge_weight = 0.0;
  {
    uvec4 band_header = texelFetch(usampler2D(band_tex, band_smp),
                     bandLoc(glyph_loc, max_band_y + 1 + band_index.x), 0);
    int curve_count = int(band_header.x);
    ivec2 entry_list_start = bandLoc(glyph_loc, int(band_header.y));
    for (int i = 0; i < curve_count && i < 128; i++) {
      ivec2 entry_coord = bandLoc(entry_list_start, i);
      uvec4 band_entry = texelFetch(usampler2D(band_tex, band_smp), entry_coord, 0);
      ivec2 curve_tex_coord = ivec2(band_entry.x, band_entry.y);
      vec4 points_01 = texelFetch(sampler2D(curve_tex, point_sampler), curve_tex_coord, 0)
              - vec4(vs_out_glyph_pos, vs_out_glyph_pos);
      ivec2 next_tex_coord = bandLoc(curve_tex_coord, 1);
      vec2 point_2 = texelFetch(sampler2D(curve_tex, point_sampler), next_tex_coord, 0).xy
              - vs_out_glyph_pos;
      if (max(max(points_01.y, points_01.w), point_2.y) * glyph_units_per_pixel.y < -0.5) break;
      uint root_mask = calcRootCode(points_01.x, points_01.z, point_2.x);
      if (root_mask != 0u) {
        vec2 crossings = solveVert(points_01, point_2) * glyph_units_per_pixel.y;
        if ((root_mask & 1u) != 0u) {
          v_winding -= clamp(crossings.x + 0.5, 0.0, 1.0);
          v_edge_weight = max(v_edge_weight, clamp(1.0 - abs(crossings.x) * 2.0, 0.0, 1.0));
        }
        if (root_mask > 1u) {
          v_winding += clamp(crossings.y + 0.5, 0.0, 1.0);
          v_edge_weight = max(v_edge_weight, clamp(1.0 - abs(crossings.y) * 2.0, 0.0, 1.0));
        }
      }
    }
  }
  float fill_coverage = max(
    abs(h_winding * h_edge_weight + v_winding * v_edge_weight)
      / max(h_edge_weight + v_edge_weight, 1.0 / 65536.0),
    min(abs(h_winding), abs(v_winding))
  );
  fill_coverage = clamp(fill_coverage, 0.0, 1.0);

  int shader_type = render_flags & 0xFF;
  int tex_type = (render_flags >> 8) & 0xFF;
  mat3 paint_transform = loadTransform(paint_transform_index);

  if (shader_type == 1) { // Solid color
    fs_out_color = vs_out_text_color * fill_coverage;
  } else if (shader_type == 2) { // Gradient
    vec2 local_pos = (paint_transform * vec3(vs_out_pos, 1.0)).xy;
    float gradient = clamp((sdfRoundRect(local_pos, extent, radius) + feather * 0.5) / feather, 0.0, 1.0);
    vec4 texel = tex_type > 0 ? texture(sampler2D(image_tex, image_smp), vec2(gradient, 0))
                : mix(vs_out_text_color, vs_out_text_color, gradient);
    if (tex_type == 1)
    texel = vec4(texel.rgb * texel.a, texel.a);
    // Combine alpha
    fs_out_color = texel * fill_coverage;
  } else if (shader_type == 3) { // Image
    vec2 local_pos = (paint_transform * vec3(vs_out_pos, 1.0)).xy / extent;
    vec4 texel = texture(sampler2D(image_tex, image_smp), local_pos);
    if (tex_type == 1)
    texel = vec4(texel.rgb * texel.a, texel.a);
    else if (tex_type == 2)
    texel = vec4(texel.r);
    texel *= vs_out_text_color;
    // backdrop 合成（premultiplied Over）：图案透明处透出底衬色（如文字实色）；
    // backdrop 全零时该项为 0，退化为纯 tint（默认行为不变）。
    // 单 pass 内完成合成 → 字形只被混合一次，消除两遍绘制的 AA 交叉项黑边。
    texel += vs_out_backdrop_color * (1.0 - texel.a);
    // Combine alpha
    fs_out_color = texel * fill_coverage;
  } else { // not used
    fs_out_color = vec4(1.0f, 0, 0, 1.0f);
  }
}

@end

@program glyph vs_glyph fs_glyph
