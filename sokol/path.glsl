@module path

@block load_transform
mat3 loadTransform(int idx) {
    return mat3(vec3(transforms[idx].t1, 0.0),
                vec3(transforms[idx].t2, 0.0),
                vec3(transforms[idx].t3, 1.0));
}
@end

@vs vs_path

layout (binding = 0) uniform vs_params {
  vec2 view_size;
  int pad;
};

in uint vs_fill_count;
in uint vs_fill_offset;
in vec4 vs_draw_rect;
in vec4 vs_fill_color;
in vec4 vs_fill_outer_color;
in vec4 vs_backdrop_color;

flat out uint vs_out_fill_count;
flat out uint vs_out_fill_offset;
flat out vec4 vs_out_fill_color;
flat out vec4 vs_out_fill_outer_color;
flat out vec4 vs_out_backdrop_color;
// flat out vec2 vs_out_view_size;
out vec2 vs_out_uv;
out vec2 vs_out_pos;

void main()
{
  vec2 quad_pos = vec2(gl_VertexIndex & 1, (gl_VertexIndex >> 1) & 1);
  vec2 vertex_pos = vs_draw_rect.xy + quad_pos * vs_draw_rect.zw;

  vs_out_pos = vertex_pos;
  vs_out_uv = quad_pos;

  vs_out_fill_count = vs_fill_count;
  vs_out_fill_offset = vs_fill_offset;
  vs_out_fill_color = vs_fill_color;
  vs_out_fill_outer_color = vs_fill_outer_color;
  vs_out_backdrop_color = vs_backdrop_color;

  float x = 2.0 * vertex_pos.x / view_size.x - 1.0;
  float y = 1.0 - 2.0 * vertex_pos.y / view_size.y;
  gl_Position = vec4(x, y, 0, 1);
}
@end

@fs fs_path

layout (binding = 1) uniform fs_params {
  vec2 extent;      // paint.extent: box-gradient half-size (gradient) / coord divisor (image)
  int paint_transform_index;
  float radius;     // box-gradient corner radius (currently always 0)
  float feather;    // gradient feather width (paint.feather)
  int render_flags;  // packed: shader_type(bits 0-7) | tex_type(bits 8-15) | fill_type(bits 16-23)
};

layout (binding = 2) uniform texture2D image_tex;
layout (binding = 3) uniform sampler image_smp;

// Flat storage buffer (SSBO) of per-contour edge data. Indexed directly by the
// linear fill offset + loop index -- no 2D-array tiling or texelFetch decode.
// sokol-shdc requires the flexible array element to be a struct, so the single
// vec4 member is wrapped in edge_item (cannot use `vec4 edges[]` directly).
struct edge_item {
  vec4 seg;
};
layout (binding = 4) readonly buffer edge_buf {
  edge_item edges[];
};

struct transform_item {
  vec2 t1;
  vec2 t2;
  vec2 t3;
};
layout (binding = 5) readonly buffer transform_buf {
  transform_item transforms[];
};

@include_block load_transform

flat in uint vs_out_fill_count;
flat in uint vs_out_fill_offset;
flat in vec4 vs_out_fill_color;
flat in vec4 vs_out_fill_outer_color;
flat in vec4 vs_out_backdrop_color;
// flat in vec2 vs_out_view_size;
in vec2 vs_out_uv;
in vec2 vs_out_pos;

out vec4 fs_out_color;

const int NVG_PATH_EVENODD = 1;

// unlike areaEdge(), this assumes pixel center is (0, 0), not (0.5, 0.5)
float pixelEdgeArea(vec2 v0, vec2 v1)
{
  if (v0.y < -0.5f && v1.y < -0.5f) // entirely below pixel
    return 0.0f;
  vec2 window = clamp(vec2(v0.x, v1.x), -0.5f, 0.5f);
  float width = window.y - window.x;
  if (width == 0.0f) // entirely left or right
    return 0.0f;
  if (v0.y > 0.5f && v1.y > 0.5f) // entirely above pixel
    return -width;
  vec2 dv = v1 - v0;
  float slope = dv.y / dv.x;
  float midx = 0.5f * (window.x + window.y);
  float y = v0.y + (midx - v0.x) * slope; // y value at middle of window
  float dy = abs(slope * width);
  // credit for this to
  // https://git.sr.ht/~eliasnaur/gio/tree/master/gpu/shaders/stencil.frag if
  // width == 1 (so midx == 0), the components of sides are: y crossing of right
  // edge of frag, y crossing
  //  of left edge, x crossing of top edge, x crossing of bottom edge.  Since we
  //  only consider positive slope (note abs() above), there are five cases
  //  (below, bottom-right, left-right, left-top, above) - the area formula
  //  below reduces to these cases thanks to the clamping of the other values to
  //  0 or 1.
  // I haven't thought carefully about the width < 1 case, but experimentally it
  // matches areaEdge()
  vec4 sides = vec4(y + 0.5f * dy, y - 0.5f * dy, (0.5f - y) / dy,
                    (-0.5f - y) / dy); // ry, ly, tx, bx
  sides = clamp(sides + 0.5f, 0.0f,
                1.0f); // shift from -0.5..0.5 to 0..1 for area calc
  float area =
      0.5f * (sides.z - sides.z * sides.y - 1.0f - sides.x + sides.x * sides.w);
  return area * width;
}

float sdfRoundRect(vec2 pt, vec2 ext, float rad)
{
  vec2 ext2 = ext - vec2(rad, rad);
  vec2 d = abs(pt) - ext2;
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rad;
}

float coverage(float winding, int fill_type)
{
  if ((fill_type & NVG_PATH_EVENODD) != 0)
    return 1.0f - abs(mod(winding, 2.0f) - 1.0f);
  return min(abs(winding), 1.0f); // non-zero fill
}

void main(void)
{
  mat3 paint_transform = loadTransform(paint_transform_index);
  int shader_type = render_flags & 0xFF;
  int tex_type = (render_flags >> 8) & 0xFF;
  int fill_type = (render_flags >> 16) & 0xFF;
  float winding = 0.0f;
  for (uint idx = 0; idx < vs_out_fill_count; ++idx) {
    vec4 edge_data = edges[vs_out_fill_offset + idx].seg;
    winding += pixelEdgeArea(edge_data.zw - vs_out_pos,
                             edge_data.xy - vs_out_pos);
  }
  float fill_coverage = coverage(winding, fill_type);
  if (shader_type == 1) { // Solid color
    fs_out_color = vs_out_fill_color * fill_coverage;
  } else if (shader_type == 2) { // Gradient
    // Calculate gradient color using box gradient
    vec2 local_pos = (paint_transform * vec3(vs_out_pos, 1.0)).xy;
    float gradient = clamp((sdfRoundRect(local_pos, extent, radius) + feather * 0.5) / feather,
                    0.0, 1.0);
    vec4 texel = tex_type > 0 ? texture(sampler2D(image_tex, image_smp), vec2(gradient, 0))
                             : mix(vs_out_fill_color, vs_out_fill_outer_color, gradient);
    if (tex_type == 1)
      texel = vec4(texel.rgb * texel.a, texel.a);
    // Combine alpha
    fs_out_color = texel * fill_coverage;
  } else if (shader_type == 3) { // Image
    // Calculate color from texture
    vec2 local_pos = (paint_transform * vec3(vs_out_pos, 1.0)).xy / extent;
    vec4 texel = texture(sampler2D(image_tex, image_smp), local_pos);
    if (tex_type == 1)
      texel = vec4(texel.rgb * texel.a, texel.a);
    else if (tex_type == 2)
      texel = vec4(texel.r);
    texel *= vs_out_fill_color;
    // backdrop 合成（premultiplied Over）：图案透明处透出底衬色；
    // backdrop 全零时该项为 0，退化为纯 tint（默认行为不变）。
    texel += vs_out_backdrop_color * (1.0 - texel.a);
    // Combine alpha
    fs_out_color = texel * fill_coverage;
  } else { // not used
    fs_out_color = vec4(1.0f, 0, 0, 1.0f);
  }
}

@end

@program path vs_path fs_path
