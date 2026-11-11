import Foundation

/// The body shader's Metal source, compiled when the app starts so the build needs no Metal toolchain.
enum BodyShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// A port of the prototype's WebGL body shader: the same orthographic camera, 8° down,
// and the same key light, sky fill, rim and baked ambient occlusion.
struct BodyUniforms {
    float c, s, cp, sp;
    float4 map;
};

struct BodyOut {
    float4 position [[position]];
    float3 normal;
    float occlusion;
};

vertex BodyOut bodyVertex(uint vid [[vertex_id]],
                          const device packed_float3 *positions [[buffer(0)]],
                          const device packed_float3 *normals [[buffer(1)]],
                          const device float *occlusion [[buffer(2)]],
                          constant BodyUniforms &u [[buffer(3)]]) {
    float3 p = positions[vid];
    float3 n = normals[vid];
    float cx = p.x * u.c + p.z * u.s, cz = -p.x * u.s + p.z * u.c, v = p.y - 220.0;
    float sy = v * u.cp + cz * u.sp + 220.0, d = cz * u.cp - v * u.sp;
    float nx = n.x * u.c + n.z * u.s, nz = -n.x * u.s + n.z * u.c;
    BodyOut out;
    out.normal = float3(nx, n.y * u.cp + nz * u.sp, nz * u.cp - n.y * u.sp);
    out.occlusion = occlusion[vid];
    // WebGL's depth ran -1...1 with nearer surfaces lower; Metal's runs 0...1.
    out.position = float4((cx + 120.0) * u.map.x + u.map.z, sy * u.map.y + u.map.w, 0.5 - d / 600.0, 1.0);
    return out;
}

fragment float4 bodyFragment(BodyOut in [[stage_in]]) {
    float3 n = normalize(in.normal);
    float3 key = normalize(float3(0.0, -0.55, 0.83));
    float3 hv = normalize(key + float3(0.0, 0.0, 1.0));
    float diff = max(0.0, dot(n, key));
    float hemi = 0.5 - 0.5 * n.y;
    float spec = pow(max(0.0, dot(n, hv)), 26.0) * 0.1;
    float rim = pow(1.0 - max(0.0, n.z), 3.0) * 0.18;
    float ao = 0.28 + 0.72 * in.occlusion;
    float shade = clamp(((0.5 * diff + 0.4 * hemi + 0.1) * ao + spec) * (1.0 - rim), 0.0, 1.0);
    return float4(mix(float3(84.0, 102.0, 106.0), float3(232.0, 239.0, 238.0), shade) / 255.0, 1.0);
}
"""#
}
