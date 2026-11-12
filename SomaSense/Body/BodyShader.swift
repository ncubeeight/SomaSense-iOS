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

// Painted areas, ported from the prototype's paint and decal shaders. Both are drawn over the body
// already drawn, on the same surface, and multiply a teal tint into it.
struct DecalUniforms {
    float c2, s2, pad0, pad1;
    float4 box;
    float4 view;
};

struct PaintOut {
    float4 position [[position]];
    float3 world;
    float2 uv;
    float facing;
};

vertex PaintOut paintVertex(uint vid [[vertex_id]],
                            const device packed_float3 *positions [[buffer(0)]],
                            const device packed_float3 *normals [[buffer(1)]],
                            constant BodyUniforms &u [[buffer(3)]],
                            constant DecalUniforms &e [[buffer(4)]]) {
    float3 p = positions[vid];
    float cx = p.x * u.c + p.z * u.s, cz = -p.x * u.s + p.z * u.c, v = p.y - 220.0;
    float sy = v * u.cp + cz * u.sp + 220.0, d = cz * u.cp - v * u.sp;
    // Where the vertex falls in the area's mask, seen from the side it was drawn on.
    float bx = p.x * e.c2 + p.z * e.s2, bz = -p.x * e.s2 + p.z * e.c2;
    PaintOut out;
    out.uv = float2((bx - e.box.x) * e.box.z, (v * u.cp + bz * u.sp + 220.0 - e.box.y) * e.box.w);
    out.facing = dot(float3(normals[vid]), e.view.xyz);
    out.world = p;
    out.position = float4((cx + 120.0) * u.map.x + u.map.z, sy * u.map.y + u.map.w, 0.5 - d / 600.0, 1.0);
    return out;
}

static float4 tint(float a) {
    return float4(mix(float3(1.0), float3(46.0, 143.0, 149.0) / 255.0, a * 0.65), 1.0);
}

// The stroke being drawn: skin within a brush of any touch, with an edge about one pixel wide.
fragment float4 strokeFragment(PaintOut in [[stage_in]],
                               const device float4 *touches [[buffer(0)]],
                               constant uint &count [[buffer(1)]]) {
    float m = 100.0;
    for (uint i = 0; i < count; i++) {
        float4 q = touches[i];
        m = min(m, distance(in.world, q.xyz) / q.w);
    }
    float a = clamp((1.0 - m) / max(fwidth(m), 1e-4) + 0.5, 0.0, 1.0);
    if (a <= 0.0) discard_fragment();
    return tint(a);
}

// A finished area, projected back onto the skin from its mask. The edge is kept about one
// screen pixel wide, so it stays crisp where the mask wraps round a limb.
fragment float4 areaFragment(PaintOut in [[stage_in]], texture2d<float> mask [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float m = mask.sample(s, in.uv).r;
    float a = clamp((m - 0.5) / max(fwidth(m), 1e-4) + 0.5, 0.0, 1.0)
            * clamp((in.facing - 0.02) / max(fwidth(in.facing), 1e-4) + 0.5, 0.0, 1.0);
    if (a <= 0.0) discard_fragment();
    return tint(a);
}
"""#
}
