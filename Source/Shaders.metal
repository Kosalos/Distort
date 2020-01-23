#include <metal_stdlib>
#include <simd/simd.h>
#import "Shaders.h"

using namespace metal;

struct Transfer {
    float4 position [[position]];
    float2 txt;
};

vertex Transfer texturedVertexShader
(
 constant TVertex* vData    [[ buffer(0) ]],
 constant ConstantData& cd  [[ buffer(1) ]],
 unsigned int vid           [[ vertex_id ]]
 )
{
    TVertex v = vData[vid];
    
    Transfer out;
    out.txt = v.txt;
    out.position = cd.mvp * float4(v.pos, 1.0);
    
    return out;
}

fragment float4 texturedFragmentShader
(
 Transfer data           [[stage_in]],
 texture2d<float> tex2D  [[texture(0)]],
 sampler sampler2D       [[sampler(0)]]
 )
{
    return tex2D.sample(sampler2D, data.txt.xy);
}

