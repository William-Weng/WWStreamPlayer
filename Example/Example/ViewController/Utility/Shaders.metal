//
//  Shaders.metal
//  Example
//
//  Created by William.Weng on 2026/3/27.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 畫一個覆蓋整個螢幕的 quad（其實是兩個三角形），用 vertex_id 生出座標與 UV
vertex VertexOut vertex_passthrough(uint vertexID [[vertex_id]]) {
    VertexOut out;

    // NDC 座標
    float2 positions[4] = {
        float2(-1.0, -1.0), // 左下
        float2( 1.0, -1.0), // 右下
        float2(-1.0,  1.0), // 左上
        float2( 1.0,  1.0)  // 右上
    };

    // 對應的 UV（依你的 pixelBuffer / 影像座標系，這裡假設原點在左上要不要翻 Y 可以自己調）
    float2 texCoords[4] = {
        float2(0.0, 1.0), // 左下
        float2(1.0, 1.0), // 右下
        float2(0.0, 0.0), // 左上
        float2(1.0, 0.0)  // 右上
    };

    uint index = vertexID % 4;

    out.position = float4(positions[index], 0.0, 1.0);
    out.texCoord = texCoords[index];
    return out;
}

// 最基本：直接把紋理畫出來（之後你要加效果就改這裡）
fragment float4 fragment_texture(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge,
                        filter::linear);
    return tex.sample(s, in.texCoord);
}
