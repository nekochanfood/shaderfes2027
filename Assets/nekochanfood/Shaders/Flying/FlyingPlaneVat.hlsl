// ============================================================================
//  FlyingPlaneVat  -  VAT から、いまの時刻の機体を読む
// ============================================================================
//  単位: シーンの単位
//
//  [テクスチャの並び]
//   横: 機体の数 × COLUMNS_PER_PLANE 列（機体の数は横幅から読む。0 = メイン、1.. = サブ）
//   縦: VAT_LOOP_SECONDS でループするフレーム
//
//  [機体ごとの列]
//   0      外接球   RGB = 中心、A = 半径
//   1〜6   頂点     RGB = 位置、A = 機体の不透明度（出入りのディザ）
//
//  ほとんどのピクセルは機体の近くを通らないので、
//  先に外接球だけを読み、レイが当たる機体だけ頂点を読む。
// ============================================================================
#ifndef FLYING_PLANE_VAT_INCLUDED
#define FLYING_PLANE_VAT_INCLUDED

// テクスチャを作る側の設定（ループの秒数・1 機の頂点数・1 機の列数）と、同じ値にしておく
#define VAT_LOOP_SECONDS 60.0
#define VERTS_PER_PLANE 6      // 0 = 機首、1 = キールの後端、2・3 / 4・5 = 両翼の付け根・先端
#define COLUMNS_PER_PLANE (1 + VERTS_PER_PLANE)

Texture2D<float4> _VatTex;
float4 _VatTex_TexelSize;

// 機体の数（メイン 1 機 + サブ）
uint PlaneCount() { return (uint)_VatTex_TexelSize.z / COLUMNS_PER_PLANE; }

// いまの時刻の前後のフレームと、その間の割合
struct VatFrame
{
    uint row0;
    uint row1;
    float blend;
};

VatFrame CurrentFrame(float time)
{
    uint frames = (uint)_VatTex_TexelSize.w;
    float f = frac(time / VAT_LOOP_SECONDS) * frames;
    VatFrame frame;
    frame.row0 = min((uint)f, frames - 1);
    frame.row1 = (frame.row0 + 1) % frames;
    frame.blend = f - frame.row0;
    return frame;
}

float4 LoadVat(uint column, VatFrame frame)
{
    return lerp(_VatTex.Load(int3(column, frame.row0, 0)), _VatTex.Load(int3(column, frame.row1, 0)), frame.blend);
}

// 機体の外接球（xyz = 中心、w = 半径）
float4 PlaneBounds(uint plane, VatFrame frame)
{
    return LoadVat(plane * COLUMNS_PER_PLANE, frame);
}

// 機体の頂点を読み、不透明度を返す
float LoadPlaneVertices(uint plane, VatFrame frame, out float3 v[VERTS_PER_PLANE])
{
    float alpha = 0;
    [unroll]
    for (uint i = 0; i < VERTS_PER_PLANE; i++)
    {
        float4 texel = LoadVat(plane * COLUMNS_PER_PLANE + 1 + i, frame);
        v[i] = texel.xyz;
        alpha = texel.w;
    }
    return alpha;
}

#endif
