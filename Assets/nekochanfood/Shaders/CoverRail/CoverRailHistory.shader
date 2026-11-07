// ============================================================================
//  CoverRailHistory
//  見ている人の位置の履歴を残す、CustomRenderTexture の更新シェーダー
// ============================================================================
//
//  [しくみ]
//   ・1 行のテクスチャを、毎フレーム 1 テクセルずつ右へずらす
//   ・左端（x = 0）に、いまの位置（xyz, ワールド座標）と時刻（w）を書く
//   ・CoverRail.shader がこの履歴をたどり、カバーが切り替わった時刻からアニメーションを進める
//
//  [CRT の設定]
//   ダブルバッファ・ポイントサンプリングにして、毎フレーム 1 回更新する。
// ============================================================================
Shader "nekochanfood/CoverRailHistory"
{
    Properties
    {
    }
    SubShader
    {
        Lighting Off
        Blend One Zero

        Pass
        {
            CGPROGRAM
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.5
            #include "UnityCustomRenderTexture.cginc"

            // VRChat のメインの画面のカメラの位置（VRChat の外では 0）
            float3 _VRChatScreenCameraPos;

            float4 frag(v2f_customrendertexture i) : SV_Target
            {
                float width = _CustomRenderTextureInfo.x;
                float x = floor(i.globalTexcoord.x * width);
                if (x < 0.5)
                {
                    float3 position = any(_VRChatScreenCameraPos != 0) ? _VRChatScreenCameraPos : _WorldSpaceCameraPos;
                    return float4(position, _Time.y);
                }
                return tex2Dlod(_SelfTexture2D, float4((x - 0.5) / width, 0.5, 0, 0));
            }
            ENDCG
        }
    }
}
