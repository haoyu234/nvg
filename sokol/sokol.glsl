@module nvg

@vs vs

layout (std140, binding = 0) uniform view {
  vec2 viewSize;
  int triangleOffset;
};

layout (binding = 6) uniform texture2DArray vertTex;
layout (binding = 7) uniform sampler smp3;

layout (location = 0) in int v_idx;
layout (location = 1) in int v_fillCount;
layout (location = 2) in int v_fillOffset;

layout (location = 0) out vec2 f_pos;
layout (location = 1) out vec2 f_vb;
layout (location = 2) flat out vec2 f_viewSize;
layout (location = 3) flat out int f_fillCount;
layout (location = 4) flat out int f_fillOffset;

#define NVG_IMAGE_TILE_WIDTH 256

vec4 vertFetch(uint idx)
{
  uint idx0 = idx;
  uint layer = idx0 / (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint idx1 = idx0 - layer * (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint row = idx1 / NVG_IMAGE_TILE_WIDTH;
  uint col = idx1 - row * NVG_IMAGE_TILE_WIDTH;
  return texelFetch(sampler2DArray(vertTex, smp3), ivec3(col, row, layer), 0);
}

void main()
{
  vec4 r = vertFetch(gl_InstanceIndex * 6 + triangleOffset + gl_VertexIndex);

  f_pos = r.xy;
  f_vb = r.zw;
  f_viewSize = viewSize;

  f_fillCount = v_fillCount;
  f_fillOffset = v_fillOffset;

  float x = 2.0 * r.x / viewSize.x - 1.0;
  float y = 1.0 - 2.0 * r.y / viewSize.y;
  gl_Position = vec4(x, y, 0, 1);
}
@end


@fs fs
precision highp float;
precision highp int;
precision highp texture2D;
precision highp texture2DArray;

layout (binding = 1) uniform texture2D imageTex;
layout (binding = 2) uniform texture2DArray edgeTex;
layout (binding = 3) uniform sampler smp1;
layout (binding = 4) uniform sampler smp2;

layout (std140, binding = 5) uniform params {
  vec4 data[6];
};

layout (location = 0) in vec2 f_pos;
layout (location = 1) in vec2 f_vb;
layout (location = 2) flat in vec2 f_viewSize;
layout (location = 3) flat in int f_fillCount;
layout (location = 4) flat in int f_fillOffset;

layout (location = 0) out vec4 outColor;

#define NVG_PATH_EVENODD 0x1
#define NVG_IMAGE_TILE_WIDTH 256

#define innerColor data[0]
#define outerColor data[1]
#define extent data[2].xy
#define texSize data[2].zw
#define transform mat3(vec3(data[3].xy, 0), vec3(data[3].zw, 0), vec3(data[4].xy, 1))
#define radius data[4].z
#define feather data[4].w
#define shaderType int(data[5].x)
#define texType int(data[5].y)
#define fillType int(data[5].z)

// unlike areaEdge(), this assumes pixel center is (0, 0), not (0.5, 0.5)
float areaEdge2(vec2 v0, vec2 v1)
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

float sdroundrect(vec2 pt, vec2 ext, float rad)
{
  vec2 ext2 = ext - vec2(rad, rad);
  vec2 d = abs(pt) - ext2;
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rad;
}

// Super-sampled SDF text rendering - super-sampling gives big improvement at very small sizes; quality is
// comparable to summed text; w/ supersamping, FPS is actually slightly lower
float sdfCov(float D, float sdfscale)
{
  // Could we use derivative info (and/or distance at pixel center) to improve?
  return D > 0.0f ? clamp((D - 0.5f) / sdfscale + radius, 0.0f, 1.0f)
                  : 0.0f; //+ 0.25f
}

float superSDF(texture2D tex, vec2 st)
{
  vec2 tex_wh = texSize; // convert from ivec2 to vec2
  // st = st + vec2(4.0)/tex_wh;  // account for 4 pixel padding in SDF
  float s =
      (32.0f / 255.0f) * transform[0][0]; // 32/255 is STBTT pixel_dist_scale
  // return sdfCov(texture(sampler2D(tex, smp1), st).r, s);  // single sample
  s = 0.5f * s; // we're sampling 4 0.5x0.5 subpixels
  float dx = transform[0][0] / tex_wh.x / 4.0f;
  float dy = transform[1][1] / tex_wh.y / 4.0f;

  // vec2 stextent = extent/tex_wh;  ... clamping doesn't seem to be necessary
  // vec2 stmin = floor(st*stextent)*stextent;
  // vec2 stmax = stmin + stextent - vec2(1.0f);
  float d11 = texture(sampler2D(tex, smp1), st + vec2(dx, dy))
                  .r; // clamp(st + ..., stmin, stmax)
  float d10 = texture(sampler2D(tex, smp1), st + vec2(dx, -dy)).r;
  float d01 = texture(sampler2D(tex, smp1), st + vec2(-dx, dy)).r;
  float d00 = texture(sampler2D(tex, smp1), st + vec2(-dx, -dy)).r;
  return 0.25f *
         (sdfCov(d11, s) + sdfCov(d10, s) + sdfCov(d01, s) + sdfCov(d00, s));
}

vec4 edgeFetch(uint idx)
{
  uint idx0 = idx;
  uint layer = idx0 / (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint idx1 = idx0 - layer * (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint row = idx1 / NVG_IMAGE_TILE_WIDTH;
  uint col = idx1 - row * NVG_IMAGE_TILE_WIDTH;
  return texelFetch(sampler2DArray(edgeTex, smp2), ivec3(col, row, layer), 0);
}

float coverage(float W)
{
  if ((fillType & NVG_PATH_EVENODD) != 0)
    return 1.0f - abs(mod(W, 2.0f) - 1.0f);
  return min(abs(W), 1.0f); // non-zero fill
}

void main(void)
{
  vec4 result;
#ifdef SOKOL_HLSL
  vec2 fpos = vec2(gl_FragCoord.x, gl_FragCoord.y);
#else
  vec2 fpos = vec2(gl_FragCoord.x, f_viewSize.y - gl_FragCoord.y);
#endif
  float W = 0.0f;
  for (uint idx = 0; idx < f_fillCount; ++idx) {
    vec4 edge = edgeFetch(f_fillOffset + idx);
    W += areaEdge2(edge.zw - fpos,
                   edge.xy - fpos); // noAA ? coversCenter(f_vb, f_pos) :
  }
  float cov = coverage(W);
  if (shaderType == 1) { // Solid color
    result = innerColor * cov;
  } else if (shaderType == 2) { // Gradient
    // Calculate gradient color using box gradient
    vec2 pt = (transform * vec3(fpos, 1.0)).xy;
    float d = clamp((sdroundrect(pt, extent, radius) + feather * 0.5) / feather,
                    0.0, 1.0);
    vec4 color = texType > 0 ? texture(sampler2D(imageTex, smp1), vec2(d, 0))
                             : mix(innerColor, outerColor, d);
    if (texType == 1)
      color = vec4(color.rgb * color.a, color.a);
    // Combine alpha
    result = color * cov;
  } else if (shaderType == 3) { // Image
    // Calculate color from texture
    vec2 pt = (transform * vec3(fpos, 1.0)).xy / extent;
    vec4 color = texture(sampler2D(imageTex, smp1), pt);
    if (texType == 1)
      color = vec4(color.rgb * color.a, color.a);
    else if (texType == 2)
      color = vec4(color.r);
    // Apply color tint and alpha.
    color *= innerColor;
    // Combine alpha
    result = color * cov;
  } else if (shaderType == 4) { // Textured tris - only used for text, so no
                                // need for coverage()
    float tcov = superSDF(imageTex, f_vb);
    result = vec4(tcov) * innerColor;
  } else { // not used
    result = vec4(1.0f, 0, 0, 1.0f);
  }

  outColor = result;
}

@end


@program nvg vs fs
