#include <metal_stdlib>
#include <simd/simd.h>
#import "Shaders.h"

using namespace metal;

struct Transfer {
    float4 position [[position]];
    float2 txt;
    int effectsEnabled;
    float bright,contrast,saturation,posterize;
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
    out.effectsEnabled = cd.effectsEnabled;
    out.bright = cd.bright;
    out.contrast = cd.contrast;
    out.saturation = cd.saturation;
    out.posterize = cd.posterize;
    return out;
}

constant float Pr = 0.299;
constant float Pg = 0.587;
constant float Pb = 0.114;

fragment float4 texturedFragmentShader
(
 Transfer data           [[stage_in]],
 texture2d<float> tex2D  [[texture(0)]],
 sampler sampler2D       [[sampler(0)]]
 )
{
    float4 color = tex2D.sample(sampler2D, data.txt.xy);
    
    if(data.effectsEnabled > 0) {
        color *= data.bright;
        color = 0.5 + (color - 0.5) * data.contrast * 2;
        
        // saturation --------------------------
        float P = sqrt(color.r * color.r * Pr + color.g * color.g * Pg + color.b * color.b * Pb);
        color.r = P + (color.r - P) * data.saturation;
        color.g = P + (color.g - P) * data.saturation;
        color.b = P + (color.b - P) * data.saturation;
        
        // posterize ---------------------------
        int temp;
        float n = 200;
        temp = int(color.r * n / data.posterize);
        color.r = float(temp) * data.posterize / 255;
        
        temp = int(color.g * n  / data.posterize);
        color.g = float(temp) * data.posterize / 255;
        
        temp = int(color.b * n / data.posterize);
        color.b = float(temp) * data.posterize / 255;
    }
    
    return color;
}

