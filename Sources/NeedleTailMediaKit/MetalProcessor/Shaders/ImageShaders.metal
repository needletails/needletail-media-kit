//
//  ImageShaders.metal
//
//
//  Created by Cole M on 7/17/24.
//
#ifdef __APPLE__

#include <metal_stdlib>
using namespace metal;

//BT.601 YUV
kernel void rgbToYuvBt601(
    texture2d<float, access::read> rgbTexture [[texture(0)]],
    texture2d<float, access::write> yTexture [[texture(1)]],
    texture2d<float, access::write> uvTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Get RGB pixel value
    float4 rgbPixel = rgbTexture.read(gid);
    
    // Convert RGB to YUV (ITU-R BT.601-4 coefficients)
    float y = 0.299 * rgbPixel.r + 0.587 * rgbPixel.g + 0.114 * rgbPixel.b;
    float u = -0.169 * rgbPixel.r - 0.331 * rgbPixel.g + 0.500 * rgbPixel.b + 0.5;
    float v = 0.500 * rgbPixel.r - 0.419 * rgbPixel.g - 0.081 * rgbPixel.b + 0.5;

    // Clamp U and V values to [0, 1] range
    u = clamp(u, 0.0, 1.0);
    v = clamp(v, 0.0, 1.0);

    // Write Y value to Y texture
    float4 yValue = float4(y, 0.0, 0.0, 1.0); // Assuming YUV format
    yTexture.write(yValue, gid);
    
    // Pack U and V values into a single float4
    float4 uvValue = float4(u, v, 0.0, 1.0);

    // Write UV value to UV texture (interleaved for kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    uvTexture.write(uvValue, uint2(gid.x / 2, gid.y / 2));
}


kernel void rgbToYuv(
    texture2d<float, access::read> rgbTexture [[texture(0)]],
    texture2d<float, access::write> yTexture [[texture(1)]],
    texture2d<float, access::write> uvTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Get RGB pixel value
    float4 rgbPixel = rgbTexture.read(gid);
    
    // Convert RGB to YUV
    float y = 0.299 * rgbPixel.r + 0.587 * rgbPixel.g + 0.114 * rgbPixel.b;
    float u = -0.14713 * rgbPixel.r - 0.28886 * rgbPixel.g + 0.436 * rgbPixel.b + 0.5; // Adjusted U
    float v = 0.615 * rgbPixel.r - 0.51499 * rgbPixel.g - 0.10001 * rgbPixel.b + 0.5; // Adjusted V

    // Clamp U and V values to [16, 240] range
    u = clamp(u * 255.0, 16.0, 240.0) / 255.0;
    v = clamp(v * 255.0, 16.0, 240.0) / 255.0;

    // Write Y value to Y texture
    float4 yValue = float4(y, 0.0, 0.0, 1.0); // Assuming YUV format
    yTexture.write(yValue, gid);
    
    // Pack U and V values into a single float4
    float4 uvValue = float4(u, v, 0.0, 1.0);

    // Write UV value to UV texture (interleaved for kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    uvTexture.write(uvValue, uint2(gid.x / 2, gid.y / 2));
}

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
    
    // Write the RGB values to the output texture
    rgbTexture.write(float4(r, g, b, 1.0), gid);
}

kernel void i420ToRgb(texture2d<float, access::read> yTexture [[texture(0)]],
                      texture2d<float, access::read> uTexture [[texture(1)]],
                      texture2d<float, access::read> vTexture [[texture(2)]],
                      texture2d<float, access::write> rgbTexture [[texture(3)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    // Get the YUV values from the input textures
    float y = yTexture.read(gid).r;
    
    // Since U and V are subsampled by 2 horizontally and vertically
    uint2 uvGid = gid / 2;
    float u = uTexture.read(uvGid).r - 0.5; // U is subsampled by 2
    float v = vTexture.read(uvGid).r - 0.5; // V is subsampled by 2
    
    // BT.601 YUV to RGB conversion
    float r = y + 1.403 * v;
    float g = y - 0.344 * u - 0.714 * v;
    float b = y + 1.770 * u;
    
    // Clamp the RGB values to the range [0, 1]
    r = clamp(r, 0.0, 1.0);
    g = clamp(g, 0.0, 1.0);
    b = clamp(b, 0.0, 1.0);
    
    
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

kernel void flipKernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                       texture2d<float, access::write> destinationTexture [[texture(1)]],
                       constant bool *horizontal [[ buffer(0) ]],
                       constant bool *vertical [[ buffer(1) ]],
                       uint2 gid [[thread_position_in_grid]]) {
    
    // Fetch texture dimensions
    const uint2 sourceSize = { sourceTexture.get_width(), sourceTexture.get_height() };
    const uint2 destinationSize = { destinationTexture.get_width(), destinationTexture.get_height() };
    
    if (gid.x < destinationSize.x && gid.y < destinationSize.y) {
        uint2 sourceCoords = gid;
        
        // Apply horizontal flip
        if (*horizontal) {
            sourceCoords.x = sourceSize.x - 1 - gid.x;
        }
        
        // Apply vertical flip
        if (*vertical) {
            sourceCoords.y = sourceSize.y - 1 - gid.y;
        }
        
        // Read from source texture and write to destination texture
        float4 color = sourceTexture.read(sourceCoords);
        destinationTexture.write(color, gid);
    }
}

kernel void combineYUVKernel(texture2d<float, access::read> yTexture [[texture(0)]],
                             texture2d<float, access::read> uvTexture [[texture(1)]],
                             texture2d<float, access::write> combinedTexture [[texture(2)]],
                             uint2 gid [[thread_position_in_grid]]) {
    // Get Y and UV values at the current thread position
    float y = yTexture.read(gid).r;
    float u = uvTexture.read(gid / 2).r - 0.5;
    float v = uvTexture.read(gid / 2).g - 0.5;
    
    // Combine YUV data into a single pixel
    float r = y + 1.402 * v;
    float g = y - 0.344136 * u - 0.714136 * v;
    float b = y + 1.772 * u;
    
    // Write the combined pixel to the output texture
    combinedTexture.write(float4(r, g, b, 1.0), gid);
}
#endif
