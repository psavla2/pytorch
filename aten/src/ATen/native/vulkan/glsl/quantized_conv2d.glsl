#version 450 core
#define PRECISION $precision
#define FORMAT    $format

layout(std430) buffer;

/* Qualifiers: layout - storage - precision - memory */

layout(set = 0, binding = 0, rgba8ui) uniform PRECISION restrict writeonly uimage3D   uOutput;
layout(set = 0, binding = 1)         uniform PRECISION                    isampler3D uInput;
layout(set = 0, binding = 2)         uniform PRECISION                    sampler3D uKernel;
layout(set = 0, binding = 3)         uniform PRECISION                    sampler3D uBias;
layout(set = 0, binding = 4)         uniform PRECISION restrict           Block {
  ivec4 size;
  ivec4 kernel;
  vec2 scale;
  ivec2 zero_point;
  ivec2 ikernel;
  ivec2 stride;
  ivec2 padding;
  ivec2 dilate;
  vec2 clamp;
} uBlock;

layout(local_size_x_id = 0, local_size_y_id = 1, local_size_z_id = 2) in;

void main() {
  const ivec3 pos = ivec3(gl_GlobalInvocationID);

  if (all(lessThan(pos, uBlock.size.xyz))) {
    const ivec2 ipos = pos.xy * uBlock.stride - uBlock.padding;

    const ivec2 start = max(ivec2(0), ipos);
    const ivec2 end = min(ipos + uBlock.kernel.xy, uBlock.kernel.zw);
    ivec2 kstart = (start - ipos) / uBlock.dilate;

    kstart.x *= 4;
    kstart.y += pos.z * uBlock.ikernel.y;

    vec4 sum = texelFetch(uBias, ivec3(pos.z, 0, 0), 0);

    for (int z4 = 0; z4 < uBlock.size.w/4; ++z4, kstart.x += uBlock.ikernel.x*4) {
      for (int y = start.y, ky = kstart.y; y < end.y; y += uBlock.dilate.y, ++ky) {
        for (int x = start.x, kx = kstart.x; x < end.x; x += uBlock.dilate.x, kx += 4) {
          const vec4 In = texelFetch(uInput, ivec3(x, y, z4), 0);
          vec4 deq_In = uBlock.scale.y * (In - uBlock.zero_point.y);
          const ivec4 kxs = kx + ivec4(0, 1, 2, 3);

          sum = fma(deq_In.xxxx, texelFetch(uKernel, ivec3(kxs.x, ky, 0), 0), sum);
          sum = fma(deq_In.yyyy, texelFetch(uKernel, ivec3(kxs.y, ky, 0), 0), sum);
          sum = fma(deq_In.zzzz, texelFetch(uKernel, ivec3(kxs.z, ky, 0), 0), sum);
          sum = fma(deq_In.wwww, texelFetch(uKernel, ivec3(kxs.w, ky, 0), 0), sum);
        }
      }
    }

    sum = clamp(sum, uBlock.clamp.x, uBlock.clamp.y);
    vec4 q_ret = sum / uBlock.scale.x + uBlock.zero_point.x;
    uvec4 res = uvec4(int(q_ret.x), int(q_ret.y), int(q_ret.z), int(q_ret.w));

    imageStore(
        uOutput,
        pos,
        res);
  }
}
