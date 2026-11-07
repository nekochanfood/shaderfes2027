// ============================================================================
//  FlyingPlaneRaymarch  -  紙飛行機の距離関数とレイマーチング
// ============================================================================
//  機体は 4 枚の三角形。機体ごとに外接球との交差を先に求め、
//  当たる区間だけをその機体だけでマーチする。
// ============================================================================
#ifndef FLYING_PLANE_RAYMARCH_INCLUDED
#define FLYING_PLANE_RAYMARCH_INCLUDED

#include "FlyingPlaneCommon.hlsl"
#include "FlyingPlaneVat.hlsl"
#include "FlyingPlaneBend.hlsl"

#define MAX_STEPS 96           // 1 機あたり
#define MAX_DIST 80.0          // 機体を探す距離（メッシュの表面から）

// 機体の三角形（頂点番号）と、影の色で塗るか（翼 = 光、キール = 影）
// 光の向きで決めると、機体の向きによっては全部が同じ色になって平らに見えるので、
// 面ごとに決めて、どの角度からでも 2 色に見えるようにする
static const int3 TRIANGLES[4] = { int3(0, 2, 3), int3(0, 1, 2), int3(0, 5, 4), int3(0, 4, 1) };
static const float SHADED[4] = { 0, 1, 0, 1 };

// 三角形までの距離（Inigo Quilez, udTriangle）
float TriangleDistance(float3 p, float3 a, float3 b, float3 c)
{
    float3 ba = b - a, pa = p - a;
    float3 cb = c - b, pb = p - b;
    float3 ac = a - c, pc = p - c;
    float3 n = cross(ba, ac);
    bool outside = sign(dot(cross(ba, n), pa)) + sign(dot(cross(cb, n), pb)) + sign(dot(cross(ac, n), pc)) < 2.0;
    return sqrt(outside
        ? min(min(Dot2(ba * saturate(dot(ba, pa) / Dot2(ba)) - pa),
                  Dot2(cb * saturate(dot(cb, pb) / Dot2(cb)) - pb)),
                  Dot2(ac * saturate(dot(ac, pc) / Dot2(ac)) - pc))
        : dot(n, pa) * dot(n, pa) / Dot2(n));
}

// 1 機ぶんの距離
// x = 光の面までの距離、y = 影の面までの距離
float2 PlaneDistance(float3 p, float3 v[VERTS_PER_PLANE])
{
    float2 result = MAX_DIST;
    [unroll]
    for (int t = 0; t < 4; t++)
    {
        int3 tri = TRIANGLES[t];
        float d = TriangleDistance(p, v[tri.x], v[tri.y], v[tri.z]);
        if (SHADED[t] > 0.5) result.y = min(result.y, d);
        else result.x = min(result.x, d);
    }
    return result;
}

// 影の色の割合（0 = 光、1 = 影）
// 2 つの面の境目では、ピクセルの幅 footprint の中で色を混ぜる
// （離れるとキールは 1 ピクセルより細くなり、どちらの色かがピクセルごとにばらついてまだらになるため）
float ShadeAmount(float2 h, float footprint)
{
    return saturate(0.5 + (h.x - h.y) / (2 * footprint));
}

// レイ（rd は単位ベクトル）が球を通る区間 (入る t, 出る t)
// 当たらなければ x > y
float2 SphereInterval(float3 ro, float3 rd, float3 center, float radius)
{
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float h = b * b - (dot(oc, oc) - radius * radius);
    if (h < 0) return float2(1, -1);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

// 頂点 v・外接球 front の機体が、ro から見て外接球 back の手前に重なっている度合い（0〜1）
// 手前の機体は外接球ではなく頂点の向きで測る（平たい機体の外接球は大きく、カメラに近いと見かけが大きくなりすぎる）
// 見える角度の重なりと、手前にいるかを、どちらもなめらかに変えて、出入りでちらつかないようにする
float CoverAmount(float3 ro, float3 v[VERTS_PER_PLANE], float4 front, float4 back)
{
    float3 toBack = back.xyz - ro;
    float db = max(length(toBack), 1e-4);
    toBack /= db;
    float closest = dot(normalize(front.xyz - ro), toBack);
    [unroll]
    for (uint k = 0; k < VERTS_PER_PLANE; k++) closest = max(closest, dot(normalize(v[k] - ro), toBack));
    float angle = acos(clamp(closest, -1, 1));
    float reach = asin(saturate(back.w / db));
    return (1 - smoothstep(0.5 * reach, reach, angle)) * smoothstep(0, front.w, db - length(front.xyz - ro));
}

struct PlaneHit
{
    float cover;      // ピクセルを覆う割合（当たったら 1、縁をかすめたら 0〜1、なければ 0）
    uint plane;       // 機体の番号（0 = メイン）
    float shade;      // 影の色の割合（ShadeAmount）
    float distance;   // レイの始点から当たった（かすめた）点まで
};

// dither は Bayer4 のしきい値（機体の不透明度がこれ以下なら描かない）
// pixelAngle は 1 ピクセルの視野角（rad）、距離 t での 1 ピクセルの幅は pixelAngle * t
// 機体は世界の曲げ（bend）に沿わせる
// 機体ごとに、外接球との交差を先に解析的に求め、当たる区間だけをその機体だけでマーチする
// 手前で当たったら、それより奥は調べない
// ro から見てメインの手前に重なるサブは、不透明度を coverOpacity 倍まで下げて透かす
// maxDistance より遠い機体は探さない
//
// 縁のアンチエイリアス: 当たらなかったレイでも、機体にいちばん近づいたところでの距離がピクセルの幅より小さければ、
// その近さに応じてピクセルを一部覆うものとして edge に返す（当たった機体より手前のものだけ）
PlaneHit MarchPlanes(float3 ro, float3 rd, VatFrame frame, float dither, WorldBend bend, float coverOpacity, float maxDistance,
                     float pixelAngle, out PlaneHit edge)
{
    PlaneHit result;
    result.cover = 0;
    result.plane = 0;
    result.shade = 0;
    result.distance = maxDistance;
    edge = result;
    uint planes = PlaneCount();
    float4 mainBounds = PlaneBounds(0, frame);
    mainBounds.xyz = MakeRigidBend(mainBounds.xyz, bend).to;
    [loop]
    for (uint p = 0; p < planes; p++)
    {
        float4 bounds = PlaneBounds(p, frame);
        RigidBend rigid = MakeRigidBend(bounds.xyz, bend);
        bounds.xyz = rigid.to;
        float2 span = SphereInterval(ro, rd, bounds.xyz, bounds.w);
        if (span.x > span.y || span.y < 0 || span.x > result.distance) continue;

        float3 v[VERTS_PER_PLANE];
        float opacity = LoadPlaneVertices(p, frame, v);
        if (opacity <= dither) continue;
        [unroll]
        for (uint k = 0; k < VERTS_PER_PLANE; k++) v[k] = ApplyRigidBend(v[k], rigid);
        if (p > 0 && opacity * lerp(1, coverOpacity, CoverAmount(ro, v, bounds, mainBounds)) <= dither) continue;

        float t = max(span.x, 0);
        float tEnd = min(span.y, result.distance);
        PlaneHit near = result;   // この機体にいちばん近づいたところ
        near.cover = 0;
        near.plane = p;
        [loop]
        for (int i = 0; i < MAX_STEPS; i++)
        {
            float2 h = PlaneDistance(ro + rd * t, v);
            float d = min(h.x, h.y);
            // 厚みのない面なので、半ピクセルまで近づいたら当たりにする（ごく近くでは止まりきれないので下限を置く）
            float footprint = max(pixelAngle * t, 0.002);
            // 半ピクセルで 1、1 ピクセルで 0 になる覆う割合
            float cover = saturate(2 - 2 * d / footprint);
            if (cover > near.cover)
            {
                near.cover = cover;
                near.shade = ShadeAmount(h, footprint);
                near.distance = t;
            }
            if (cover >= 1)
            {
                result = near;
                break;
            }
            t += d;
            if (t > tEnd) break;
        }
        if (near.cover < 1 && near.cover > edge.cover) edge = near;
    }
    // 当たった機体より奥の縁は、当たった機体に隠れる
    if (edge.distance > result.distance) edge.cover = 0;
    return result;
}

#endif
