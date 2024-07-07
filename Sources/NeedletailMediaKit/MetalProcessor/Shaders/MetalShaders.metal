//
//  MetalShaders.metal
//  
//
//  Created by Cole M on 7/4/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void ycbcrToRgb(texture2d<float, access::read> yTexture [[texture(0)]],
                           texture2d<float, access::read> uvTexture [[texture(1)]],
                           texture2d<float, access::write> rgbTexture [[texture(2)]],
                           uint2 gid [[thread_position_in_grid]]) {
    
    // Get the YUV values from the input textures
    float y = yTexture.read(gid).r;
    float u = uvTexture.read(gid / 2).r - 0.5;
    float v = uvTexture.read(gid / 2).g - 0.5;
    
    // BT.601 YUV to RGB conversion
    float r = y + 1.402 * v;
    float g = y - 0.344136 * u - 0.714136 * v;
    float b = y + 1.772 * u;
    
    // BT.709 YUV to RGB conversion
//    float r = y + 1.5748 * v;
//    float g = y - 0.1873 * u - 0.4681 * v;
//    float b = y + 1.8556 * u;
    
    // Write the RGB values to the output texture
    rgbTexture.write(float4(r, g, b, 1.0), gid);
}


typedef struct {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
} TextureMappingVertex;

vertex TextureMappingVertex mapTexture(unsigned int vertex_id [[ vertex_id ]]) {
    float4x4 renderedCoordinates = float4x4(float4( -1.0, -1.0, 0.0, 1.0 ),
                                            float4(  1.0, -1.0, 0.0, 1.0 ),
                                            float4( -1.0,  1.0, 0.0, 1.0 ),
                                            float4(  1.0,  1.0, 0.0, 1.0 ));

    float4x2 textureCoordinates = float4x2(float2( 0.0, 1.0 ),
                                           float2( 1.0, 1.0 ),
                                           float2( 0.0, 0.0 ),
                                           float2( 1.0, 0.0 ));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];
    
    return outVertex;
}

fragment half4 displayTexture(TextureMappingVertex mappingVertex [[ stage_in ]],
                              texture2d<float, access::sample> texture [[ texture(0) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    return half4(texture.sample(s, mappingVertex.textureCoordinate));
}

struct VertexIn {
    float4 position [[ attribute(0) ]];
    float2 texCoord [[ attribute(1) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float2 texCoord;
};

vertex VertexOut vertex_shader(VertexIn in [[ stage_in ]],
                               constant float4x4 &modelViewProjection [[ buffer(0) ]]) {
    VertexOut out;
    
    // Transform vertex position
    out.position = modelViewProjection * in.position;
    
    // Pass through texture coordinates
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 fragment_shader(VertexOut vertex_out [[ stage_in ]],
                                texture2d<float, access::sample> texture [[ texture(0) ]],
                                sampler sampler_linear [[ sampler(0) ]]) {
    
    // Flip texture horizontally
    float2 flipped_tex_coords = float2(1.0 - vertex_out.texCoord.x, vertex_out.texCoord.y);
    
    // Sample texture
    float4 color = texture.sample(sampler_linear, flipped_tex_coords);
    
    return color;
}
