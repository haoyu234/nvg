@module contour

@vs vs_contour

layout (std140, binding = 0) uniform v_params {
  vec2 viewSize;
  int vertexOffset;
};

layout (binding = 1) uniform texture2DArray vertTex;
layout (binding = 2) uniform sampler vertSmp;

layout (binding = 8) uniform texture2DArray colorTex;
layout (binding = 9) uniform sampler colorSmp;

layout (location = 0) in int v_idx;
layout (location = 1) in int v_fillCount;
layout (location = 2) in int v_fillOffset;
layout (location = 3) in int v_colorIndex;
layout (location = 4) in int v_pad;

layout (location = 0) flat out vec2 f_viewSize;
layout (location = 1) flat out int f_fillCount;
layout (location = 2) flat out int f_fillOffset;
layout (location = 3) flat out vec4 f_color;
layout (location = 4) out vec2 f_uv;

#define NVG_IMAGE_TILE_WIDTH 256

vec4 vec4Fetch(texture2DArray tex, sampler smp, uint idx)
{
  uint idx0 = idx;
  uint layer = idx0 / (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint idx1 = idx0 - layer * (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint row = idx1 / NVG_IMAGE_TILE_WIDTH;
  uint col = idx1 - row * NVG_IMAGE_TILE_WIDTH;
  return texelFetch(sampler2DArray(tex, smp), ivec3(col, row, layer), 0);
}

void main()
{
  vec4 r = vec4Fetch(vertTex, vertSmp, gl_InstanceIndex * 4 + vertexOffset + gl_VertexIndex);
  vec2 pos = r.xy;

  f_viewSize = viewSize;
  f_uv = r.zw;

  f_fillCount = v_fillCount;
  f_fillOffset = v_fillOffset;
  f_color = vec4Fetch(colorTex, colorSmp, v_colorIndex);

  float x = 2.0 * pos.x / viewSize.x - 1.0;
  float y = 1.0 - 2.0 * pos.y / viewSize.y;
  gl_Position = vec4(x, y, 0, 1);
}
@end

@fs fs_contour
precision highp float;
precision highp int;
precision highp texture2D;
precision highp texture2DArray;

layout (std140, binding = 3) uniform f_params {
  vec4 data[6];
};

layout (binding = 4) uniform texture2D imageTex;
layout (binding = 5) uniform sampler imageSmp;

layout (binding = 6) uniform texture2DArray edgeTex;
layout (binding = 7) uniform sampler edgeSmp;

layout (location = 0) flat in vec2 f_viewSize;
layout (location = 1) flat in int f_fillCount;
layout (location = 2) flat in int f_fillOffset;
layout (location = 3) flat in vec4 f_color;
layout (location = 4) in vec2 f_uv;

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
#define isSdf bool(data[5].w)

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

vec4 vec4Fetch(texture2DArray tex, sampler smp, uint idx)
{
  uint idx0 = idx;
  uint layer = idx0 / (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint idx1 = idx0 - layer * (NVG_IMAGE_TILE_WIDTH * NVG_IMAGE_TILE_WIDTH);
  uint row = idx1 / NVG_IMAGE_TILE_WIDTH;
  uint col = idx1 - row * NVG_IMAGE_TILE_WIDTH;
  return texelFetch(sampler2DArray(tex, smp), ivec3(col, row, layer), 0);
}

float coverage(float w)
{
  if ((fillType & NVG_PATH_EVENODD) != 0)
    return 1.0f - abs(mod(w, 2.0f) - 1.0f);
  return min(abs(w), 1.0f); // non-zero fill
}

vec4 sdf(vec4 col) {
	float d = (col.a - (128.0/255.0)) / (32.0/255.0);
	float w = 0.8 / 0.46875;
	float a = 1.f - clamp((d + 0.5*w - 0.1) / w, 0.0, 1.0);
	return vec4(col.rgb * a, a); // premultiply
}

void main(void)
{
  vec4 result;
#ifdef SOKOL_HLSL
  vec2 fpos = vec2(gl_FragCoord.x, gl_FragCoord.y);
#else
  vec2 fpos = vec2(gl_FragCoord.x, f_viewSize.y - gl_FragCoord.y);
#endif
  float w = 0.0f;
  for (uint idx = 0; idx < f_fillCount; ++idx) {
    vec4 edge = vec4Fetch(edgeTex, edgeSmp, f_fillOffset + idx);
    w += areaEdge2(edge.zw - fpos,
                   edge.xy - fpos);
  }
  float cov = coverage(w);
  if (shaderType == 1) { // Solid color
    result = innerColor * cov;
  } else if (shaderType == 2) { // Gradient
    // Calculate gradient color using box gradient
    vec2 pt = (transform * vec3(fpos, 1.0)).xy;
    float d = clamp((sdroundrect(pt, extent, radius) + feather * 0.5) / feather,
                    0.0, 1.0);
    vec4 texColor = texType > 0 ? texture(sampler2D(imageTex, imageSmp), vec2(d, 0))
                             : mix(innerColor, outerColor, d);
    if (texType == 1)
      texColor = vec4(texColor.rgb * texColor.a, texColor.a);
    // Combine alpha
    result = texColor * cov;
  } else if (shaderType == 3) { // Image
    // Calculate color from texture
    vec2 pt = (transform * vec3(fpos, 1.0)).xy / extent;
    vec4 texColor = texture(sampler2D(imageTex, imageSmp), pt);
    if (texType == 1)
      texColor = vec4(texColor.rgb * texColor.a, texColor.a);
    else if (texType == 2)
      texColor = vec4(texColor.r);
    // Apply color tint and alpha.
    texColor *= innerColor;
    // Combine alpha
    result = texColor * cov;
  } else if (shaderType == 4) { // GlyphQuad
    vec4 texColor = texture(sampler2D(imageTex, imageSmp), f_uv);
    if (texType == 1)
      texColor = vec4(texColor.rgb * texColor.a, texColor.a);
    else if (texType == 2) {
      texColor = vec4(texColor.r);
    }

    if (isSdf) {
      texColor = sdf(texColor);
    }

    result = texColor * f_color;
  } else { // not used
    result = vec4(1.0f, 0, 0, 1.0f);
  }

  outColor = result;
}

@end

@program glsl_contour vs_contour fs_contour
