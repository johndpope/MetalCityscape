#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float3 worldPos;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

struct UniformsWithColor {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4 color;
};

struct UniformsWithAlpha {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float alpha;
};

vertex VertexOut wireframeVertexShader(VertexIn in [[stage_in]],
                                       constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPos = worldPos.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 wireframeFragmentShader(VertexOut in [[stage_in]]) {
    float3 wireframeColor = float3(0.0, 0.8, 1.0);
    float distance = length(in.worldPos);
    float fade = 1.0 - smoothstep(10.0, 50.0, distance);
    return float4(wireframeColor * fade, 1.0);
}

vertex VertexOut coloredWireframeVertexShader(VertexIn in [[stage_in]],
                                              constant UniformsWithColor &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPos = worldPos.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 coloredWireframeFragmentShader(VertexOut in [[stage_in]],
                                               constant UniformsWithColor &uniforms [[buffer(1)]]) {
    float distance = length(in.worldPos);
    float fade = 1.0 - smoothstep(10.0, 50.0, distance);
    
    // Add pulsing effect for hovered items
    float time = uniforms.color.w; // Use alpha channel for time
    float pulse = 0.5 + 0.5 * sin(time * 4.0);
    float intensity = 0.7 + 0.3 * pulse;
    
    // Make wireframes semi-transparent (0.5 alpha)
    return float4(uniforms.color.rgb * fade * intensity, 1);
}

vertex VertexOut textureVertexShader(VertexIn in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPos = worldPos.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 textureFragmentShader(VertexOut in [[stage_in]],
                                     texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 color = texture.sample(textureSampler, in.texCoord);
    
    float distance = length(in.worldPos);
    float fade = 1.0 - smoothstep(20.0, 60.0, distance);
    color.rgb *= fade;
    
    float glow = 0.2;
    color.rgb += float3(0.1, 0.2, 0.3) * glow;
    
    return color;
}

vertex VertexOut transparentTextureVertexShader(VertexIn in [[stage_in]],
                                               constant UniformsWithAlpha &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPos = worldPos.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 transparentTextureFragmentShader(VertexOut in [[stage_in]],
                                                texture2d<float> texture [[texture(0)]],
                                                constant UniformsWithAlpha &uniforms [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 color = texture.sample(textureSampler, in.texCoord);
    
    float distance = length(in.worldPos);
    float fade = 1.0 - smoothstep(20.0, 60.0, distance);
    color.rgb *= fade;
    
    float glow = 0.2;
    color.rgb += float3(0.1, 0.2, 0.3) * glow;
    
    // Apply custom alpha for transparency
    color.a *= uniforms.alpha;
    
    return color;
}
