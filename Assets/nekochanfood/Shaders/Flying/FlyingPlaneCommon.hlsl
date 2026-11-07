// ============================================================================
//  FlyingPlaneCommon  -  FlyingPlane の各ファイルで使う小さな汎用関数
// ============================================================================
#ifndef FLYING_PLANE_COMMON_INCLUDED
#define FLYING_PLANE_COMMON_INCLUDED

#define FLYING_PLANE_PI 3.14159265

float Dot2(float3 v) { return dot(v, v); }

// GLSL の mod（負の数でも 0〜y を返す、HLSL の fmod とは違う）
float2 GlslMod(float2 x, float y) { return x - y * floor(x / y); }

// 2D の回転（radian、反時計回り）
float2 Rotate2D(float2 v, float angle)
{
    float s, c;
    sincos(angle, s, c);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// PCG ハッシュ（32 bit の整数を混ぜる）
uint Pcg(uint v)
{
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// シード（整数）から、0〜1 の乱数を 3 つ
float3 SeedRandom(float seed)
{
    uint a = Pcg((uint)max(seed, 0));
    uint b = Pcg(a);
    uint c = Pcg(b);
    return float3(a, b, c) * (1.0 / 4294967296.0);
}

// 4x4 のベイヤー行列のしきい値（0〜1）
// 不透明度がこれを超えたピクセルだけを描くと、ディザのフェードになる
float Bayer4(float2 pixel)
{
    static const float M[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    uint2 q = uint2(pixel) & 3;
    return (M[q.y * 4 + q.x] + 0.5) / 16.0;
}

#endif
