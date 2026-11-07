// ============================================================================
//  FlyingPlaneBend  -  世界の曲げ（_GroundCurvature）
// ============================================================================
//  地面を球面に曲げ、機体もそれに沿わせる。
//    曲率 > 0 : 機体の下に丸まる球の外側（小さな惑星）
//    曲率 < 0 : 機体を包む球の内側
//  地面の模様（FlyingPlaneGround.hlsl）と機体（FlyingPlaneRaymarch.hlsl）は、
//  どちらもここの曲げ方を使う。
// ============================================================================
#ifndef FLYING_PLANE_BEND_INCLUDED
#define FLYING_PLANE_BEND_INCLUDED

#define CURVATURE_EPSILON 1e-3  // これより平らなら平面として扱う

struct WorldBend
{
    float height;     // 機体の原点から地面までの高さ
    float curvature;  // -1〜1
};

// 曲げた地面の球
// 半径は height / curvature^2（0 の近くはゆるやかに、±1 に近づくほど強く曲がる）
// -1 で、球の中心が機体の高さに来る
struct GroundSphere
{
    float side;       // 地面の上（機体のいる側）が球の外なら 1、内なら -1
    float radius;
    float3 center;
    float3 pole;      // 球の中心から見た、機体の真下の点の向き
};

bool IsFlat(WorldBend b) { return abs(b.curvature) < CURVATURE_EPSILON; }

GroundSphere MakeGroundSphere(WorldBend b)
{
    GroundSphere g;
    g.side = sign(b.curvature);
    g.radius = b.height / (b.curvature * b.curvature);
    g.center = float3(0, -b.height - g.side * g.radius, 0);
    g.pole = float3(0, g.side, 0);
    return g;
}

// 平らな世界の点を、曲げた世界へ移す
// 機体の真下の点からの水平距離を球面に沿った弧の長さとして巻きつけ、
// 地面からの高さはそのまま保つ（地面の模様の uv はこの逆）
float3 BendPoint(float3 p, WorldBend b)
{
    if (IsFlat(b)) return p;
    GroundSphere g = MakeGroundSphere(b);
    float r = length(p.xz);
    float2 dir = r > 1e-5 ? p.xz / r : 0;
    float theta = r / g.radius;
    float3 n = float3(sin(theta) * dir.x, g.side * cos(theta), sin(theta) * dir.y);
    return g.center + n * (g.radius + g.side * (p.y + b.height));
}

// 物体を、形を変えずに（剛体のまま）曲げた世界へ移す動き
// 中心は BendPoint で移し、向きは、その位置で地面が
// 傾いている分だけ回す（点ごとに BendPoint で曲げると、高さによって大きさが変わってしまうため）
struct RigidBend
{
    float3 from;      // 平らな世界での中心
    float3 to;        // 曲げた世界での中心
    float3 axis;      // 回す軸（単位ベクトル）
    float2 sinCos;    // 回す角度の sin, cos
};

RigidBend MakeRigidBend(float3 center, WorldBend b)
{
    RigidBend r;
    r.from = center;
    r.to = BendPoint(center, b);
    float distance = length(center.xz);
    float2 dir = distance > 1e-5 ? center.xz / distance : float2(1, 0);
    // 上向きを水平の向き dir の側へ倒す軸
    // 角度は、外側の球なら外へ、内側の球なら内へ
    r.axis = float3(dir.y, 0, -dir.x);
    float angle = 0;
    if (!IsFlat(b))
    {
        GroundSphere g = MakeGroundSphere(b);
        angle = g.side * distance / g.radius;
    }
    sincos(angle, r.sinCos.x, r.sinCos.y);
    return r;
}

float3 ApplyRigidBend(float3 v, RigidBend r)
{
    // ロドリゲスの回転公式
    float3 d = v - r.from;
    float3 rotated = d * r.sinCos.y + cross(r.axis, d) * r.sinCos.x + r.axis * dot(r.axis, d) * (1 - r.sinCos.y);
    return r.to + rotated;
}

#endif
