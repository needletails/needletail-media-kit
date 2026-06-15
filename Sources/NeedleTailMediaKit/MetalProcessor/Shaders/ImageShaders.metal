//
//  ImageShaders.metal
//
//
//  Created by Cole M on 7/17/24.
//
#ifdef __APPLE__

#include <metal_stdlib>
using namespace metal;

// Define the kernel function
kernel void ycbcrToRGBKernel(texture2d<half, access::read> yuvTexture [[ texture(0) ]],
                              texture2d<half, access::write> rgbTexture [[ texture(1) ]],
                              uint2 gid [[ thread_position_in_grid ]]) {
    half4 yuv = yuvTexture.read(gid);
    half y  = yuv.y; // Y
    half cb = yuv.z; // Cb
    half cr = yuv.x; // Cr
    
    // Light-weight matrix form (avoids float4x4 multiply and multiple reads).
    // Note: coefficients preserved from the original kernel.
    half r = y + half(1.4020) * cr + half(-0.7010);
    half g = y + half(-0.3441) * cb + half(-0.7141) * cr + half(0.5291);
    half b = y + half(1.7720) * cb + half(-0.8860);
    
    half4 rgba = half4(saturate(r), saturate(g), saturate(b), half(1.0));
    rgbTexture.write(rgba, gid);
}


//BT.601 YUV
kernel void rgbToYuvBt601(
                          texture2d<half, access::read> rgbTexture [[texture(0)]],
                          texture2d<half, access::write> yTexture [[texture(1)]],
                          texture2d<half, access::write> uvTexture [[texture(2)]],
                          uint2 gid [[thread_position_in_grid]]
                          ) {
                              const uint width = yTexture.get_width();
                              const uint height = yTexture.get_height();
                              if (gid.x >= width || gid.y >= height) { return; }
                              
                              // Per-pixel luma
                              half4 rgb = rgbTexture.read(gid);
                              half y = half(0.299) * rgb.r + half(0.587) * rgb.g + half(0.114) * rgb.b;
                              yTexture.write(half4(y, half(0.0), half(0.0), half(1.0)), gid);
                              
                              // UV subsampling: only one thread writes each UV pixel.
                              if ((gid.x & 1u) != 0u || (gid.y & 1u) != 0u) { return; }
                              
                              uint2 p0 = gid;
                              uint2 p1 = uint2(min(gid.x + 1u, width  - 1u), gid.y);
                              uint2 p2 = uint2(gid.x, min(gid.y + 1u, height - 1u));
                              uint2 p3 = uint2(min(gid.x + 1u, width  - 1u), min(gid.y + 1u, height - 1u));
                              
                              half3 c0 = rgbTexture.read(p0).rgb;
                              half3 c1 = rgbTexture.read(p1).rgb;
                              half3 c2 = rgbTexture.read(p2).rgb;
                              half3 c3 = rgbTexture.read(p3).rgb;
                              half3 avg = (c0 + c1 + c2 + c3) * half(0.25);
                              
                              half u = half(-0.169) * avg.r + half(-0.331) * avg.g + half(0.500) * avg.b + half(0.5);
                              half v = half(0.500) * avg.r + half(-0.419) * avg.g + half(-0.081) * avg.b + half(0.5);
                              
                              u = saturate(u);
                              v = saturate(v);
                              
                              uvTexture.write(half4(u, v, half(0.0), half(1.0)), uint2(gid.x / 2u, gid.y / 2u));
                          }


kernel void rgbToYuv(
                     texture2d<half, access::read> rgbTexture [[texture(0)]],
                     texture2d<half, access::write> yTexture [[texture(1)]],
                     texture2d<half, access::write> uvTexture [[texture(2)]],
                     uint2 gid [[thread_position_in_grid]]
                     ) {
                         const uint width = yTexture.get_width();
                         const uint height = yTexture.get_height();
                         if (gid.x >= width || gid.y >= height) { return; }
                         
                         // Per-pixel luma
                         half4 rgb = rgbTexture.read(gid);
                         half y = half(0.299) * rgb.r + half(0.587) * rgb.g + half(0.114) * rgb.b;
                         yTexture.write(half4(y, half(0.0), half(0.0), half(1.0)), gid);
                         
                         // UV subsampling (single-writer per UV pixel) using 2x2 average.
                         if ((gid.x & 1u) != 0u || (gid.y & 1u) != 0u) { return; }
                         
                         uint2 p0 = gid;
                         uint2 p1 = uint2(min(gid.x + 1u, width  - 1u), gid.y);
                         uint2 p2 = uint2(gid.x, min(gid.y + 1u, height - 1u));
                         uint2 p3 = uint2(min(gid.x + 1u, width  - 1u), min(gid.y + 1u, height - 1u));
                         
                         half3 c0 = rgbTexture.read(p0).rgb;
                         half3 c1 = rgbTexture.read(p1).rgb;
                         half3 c2 = rgbTexture.read(p2).rgb;
                         half3 c3 = rgbTexture.read(p3).rgb;
                         half3 avg = (c0 + c1 + c2 + c3) * half(0.25);
                         
                         half u = half(-0.14713) * avg.r + half(-0.28886) * avg.g + half(0.436) * avg.b + half(0.5);
                         half v = half(0.615) * avg.r + half(-0.51499) * avg.g + half(-0.10001) * avg.b + half(0.5);
                         
                         // Clamp U and V to [16, 240] in 8-bit normalized space.
                         u = clamp(u * half(255.0), half(16.0), half(240.0)) / half(255.0);
                         v = clamp(v * half(255.0), half(16.0), half(240.0)) / half(255.0);
                         
                         uvTexture.write(half4(u, v, half(0.0), half(1.0)), uint2(gid.x / 2u, gid.y / 2u));
                     }


kernel void ycbcrToRgb(texture2d<half, access::read> yTexture [[texture(0)]],
                       texture2d<half, access::read> uvTexture [[texture(1)]],
                       texture2d<half, access::write> rgbTexture [[texture(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
    
    // Most WebRTC-decoded Apple video frames arrive as limited-range YUV.
    // Use BT.709 video-range coefficients so remote H264/HD content does not skew green.
    half y = yTexture.read(gid).r;
    half2 uv = uvTexture.read(gid / 2).rg - half2(0.5h, 0.5h);
    half u = uv.x;
    half v = uv.y;
    half yPrime = max(y - half(16.0h / 255.0h), half(0.0h)) * half(255.0h / 219.0h);
    
    half r = yPrime + half(1.7927411h) * v;
    half g = yPrime - half(0.2132486h) * u - half(0.5329093h) * v;
    half b = yPrime + half(2.1124018h) * u;
    
    // Write the RGB values to the output texture
    rgbTexture.write(half4(saturate(r), saturate(g), saturate(b), half(1.0)), gid);
}

kernel void i420ToRgb(texture2d<half, access::read> yTexture [[texture(0)]],
                      texture2d<half, access::read> uTexture [[texture(1)]],
                      texture2d<half, access::read> vTexture [[texture(2)]],
                      texture2d<half, access::write> rgbTexture [[texture(3)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    half y = yTexture.read(gid).r;
    
    uint2 uvGid = gid / 2;
    half u = uTexture.read(uvGid).r - half(0.5);
    half v = vTexture.read(uvGid).r - half(0.5);
    half yPrime = max(y - half(16.0h / 255.0h), half(0.0h)) * half(255.0h / 219.0h);
    
    // Match NV12 conversion: BT.709 video-range for Apple/WebRTC remote video.
    half r = yPrime + half(1.7927411h) * v;
    half g = yPrime - half(0.2132486h) * u - half(0.5329093h) * v;
    half b = yPrime + half(2.1124018h) * u;
    
    
    // Write the RGB values to the output texture
    rgbTexture.write(half4(saturate(r), saturate(g), saturate(b), half(1.0)), gid);
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
                              texture2d<half, access::sample> texture [[ texture(0) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    return half4(texture.sample(s, mappingVertex.textureCoordinate));
}

kernel void flipKernel(texture2d<half, access::read> sourceTexture [[texture(0)]],
                       texture2d<half, access::write> destinationTexture [[texture(1)]],
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
        half4 color = sourceTexture.read(sourceCoords);
        destinationTexture.write(color, gid);
    }
}

kernel void combineYUVKernel(texture2d<half, access::read> yTexture [[texture(0)]],
                             texture2d<half, access::read> uvTexture [[texture(1)]],
                             texture2d<half, access::write> combinedTexture [[texture(2)]],
                             uint2 gid [[thread_position_in_grid]]) {
    // Get Y and UV values at the current thread position
    half y = yTexture.read(gid).r;
    half2 uv = uvTexture.read(gid / 2).rg - half2(0.5h, 0.5h);
    half u = uv.x;
    half v = uv.y;
    
    // Combine YUV data into a single pixel
    half r = y + half(1.403) * v;
    half g = y - half(0.344) * u - half(0.714) * v;
    half b = y + half(1.770) * u;
    
    // Write the combined pixel to the output texture
    combinedTexture.write(half4(saturate(r), saturate(g), saturate(b), half(1.0)), gid);
}
#endif
