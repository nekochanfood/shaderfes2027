// ============================================================================
//  FlyingPlaneGround  -  地形
// ============================================================================
//  大きさの違う 3 つの値ノイズを重ねて 2 値化した海岸線が、機体と逆向き（-x）へ流れる。
//  ノイズの格子の周期を大きく（PERIOD マス）して、長く見ても繰り返しが目立たないようにする。
//  地面の曲げ方は FlyingPlaneBend.hlsl。
// ============================================================================
#ifndef FLYING_PLANE_GROUND_INCLUDED
#define FLYING_PLANE_GROUND_INCLUDED

#include "FlyingPlaneCommon.hlsl"
#include "FlyingPlaneBend.hlsl"

#define GROUND_HALF_SIZE 150.0
#define GROUND_FADE_START 120.0 // ここから端まで背景色へ溶かす（地面の端を見せない、遠さの霞みは FlyingPlane.shader のフォグ）
#define CELL 2.8
#define PERIOD 8192.0           // ノイズの格子の周期（マス）、整数ハッシュなので大きくしても精度が落ちない
#define COAST 0.47
#define GROUND_LOOP (2.0 * PERIOD * CELL) // 広域ノイズを含めて模様が一周する距離
#define ANTIPODE_FADE_START (0.75 * FLYING_PLANE_PI) // 球の裏側（機体の真下の点の反対側）は模様が縮むので、ここから背景色へ溶かす

struct GroundPattern
{
    float speed;      // 流れる速さ（シーンの単位 / s）
    float scale;      // 模様の大きさの倍率
    float2 offset;    // 模様の位置のずれ（模様の単位）、マテリアルのシードで変える
};

struct GroundHit
{
    bool hit;
    float3 color;
    float distance;   // レイの始点から当たった点まで
};

// 格子点の乱数（0〜1）
// sin を使うハッシュは大きな座標で崩れるので、整数で混ぜる
float Hash(float2 i)
{
    uint2 q = uint2(GlslMod(i, PERIOD)) * uint2(1597334673u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334673u;
    return (n >> 8) * (1.0 / 16777216.0);
}

float ValueNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = p - i;
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return lerp(lerp(Hash(i), Hash(i + float2(1, 0)), f.x),
                lerp(Hash(i + float2(0, 1)), Hash(i + float2(1, 1)), f.x), f.y);
}

// レイと地面の交点
// uv は地面に沿った平面の座標（球なら、機体の真下の点を中心に、そこからの弧の長さで広げる）
// angle は球の中心から見た、機体の真下の点との角度（平面なら 0）
bool IntersectGround(float3 ro, float3 rd, WorldBend bend, out float2 uv, out float angle, out float distance)
{
    angle = 0;
    if (IsFlat(bend))
    {
        float t = (-bend.height - ro.y) / min(rd.y, -1e-5);
        distance = max(t, 0);
        float3 p = ro + rd * distance;
        uv = p.xz;
        return rd.y < 0 && ro.y > -bend.height;
    }

    GroundSphere g = MakeGroundSphere(bend);
    float3 oc = ro - g.center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - g.radius * g.radius;
    float disc = b * b - c;
    float root = sqrt(max(disc, 0));
    // 外側は手前の交点（外から当たる面）、内側は奥の交点（内から当たる面）
    float t = g.side > 0 ? -b - root : -b + root;
    distance = max(t, 0);
    float3 n = normalize(ro + rd * distance - g.center);
    angle = acos(clamp(dot(n, g.pole), -1, 1));
    float2 around = n.xz;
    uv = around * (angle * g.radius / max(length(around), 1e-5));
    return disc > 0 && t > 0 && (g.side < 0 || c > 0);
}

// 地面の色
// low = 低い面（背景色と同じ）、high = 高い面
// fwidth を使うので、当たるかどうかに関わらず全ピクセルで呼ぶ
GroundHit TraceGround(float3 ro, float3 rd, WorldBend bend, GroundPattern pattern, float time, float3 low, float3 high)
{
    float2 uv;
    float angle;
    GroundHit g;
    g.hit = IntersectGround(ro, rd, bend, uv, angle, g.distance);

    // 模様は z を反転した座標で作る（VAT の機体と同じ右手系の座標にそろえる）
    // 流れは模様が一周する距離で折り返して精度を保つ
    float2 flipped = float2(uv.x, -uv.y);
    float scroll = fmod(pattern.speed * time / pattern.scale, GROUND_LOOP);
    float2 p = (flipped / pattern.scale + pattern.offset + float2(scroll, 0)) / CELL;
    float v = 0.7 * ValueNoise(p * 0.5) + 0.25 * ValueNoise(p) + 0.05 * ValueNoise(p * 2.0 + 17.0);
    float w = fwidth(v) * 0.8 + 0.002;
    g.color = lerp(low, high, smoothstep(COAST - w, COAST + w, v));

    float edge = max(abs(uv.x), abs(uv.y));
    float fade = max(smoothstep(GROUND_FADE_START, GROUND_HALF_SIZE, edge),
                     smoothstep(ANTIPODE_FADE_START, FLYING_PLANE_PI, angle));
    g.color = lerp(g.color, low, fade);
    g.hit = g.hit && edge < GROUND_HALF_SIZE;
    return g;
}

#endif
