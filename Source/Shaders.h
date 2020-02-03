#pragma once
#include <simd/simd.h>

struct TVertex {
    vector_float3 pos;
    vector_float2 txt;
};

struct ConstantData {
    matrix_float4x4 mvp;
    int effectsEnabled;
    float bright,contrast,saturation,posterize;
};
