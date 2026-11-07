// ============================================================================
//  FlyingPlane
//  紙飛行機が地形の上を飛ぶ景色を、メッシュの中に描くレイマーチングのシェーダー
// ============================================================================
//
//  [概要]
//   ・任意のメッシュを「窓」にして、カメラからオブジェクト空間へレイを飛ばす
//     （メッシュの外にある機体も、表面で切れずに描かれる）
//   ・機体: VAT で動く三角形の距離関数    地形: 値ノイズの海岸線
//   ・地面は球面に曲げられ、機体もそれに沿う（_GroundCurvature）
//
//  [スケール]
//   シーンの単位は「メインの機体の長さ ≒ 3」。
//   メインの機体の原点 = オブジェクトの原点に、_SceneScale 倍して置く。
//
//  [構成]
//   FlyingPlane.shader         このファイル（プロパティ、色、フォグ、描画の流れ）
//   FlyingPlaneVat.hlsl        VAT から機体の頂点を読む
//   FlyingPlaneRaymarch.hlsl   機体の距離関数とレイマーチング
//   FlyingPlaneGround.hlsl     地形
//   FlyingPlaneBend.hlsl       世界の曲げ
//   FlyingPlaneCommon.hlsl     共通の小さな関数
// ============================================================================
Shader "nekochanfood/FlyingPlane"
{
    Properties
    {
        [NoScaleOffset] _VatTex ("Vertex Animation Texture", 2D) = "black" {}
        _Dark ("Theme (0 = Light, 1 = Dark)", Range(0, 1)) = 0
        // マテリアルごとの乱数
        // 飛行のタイミング（VAT の再生位置）と地形の模様の位置が変わる
        [IntRange] _Seed ("Seed", Range(0, 9999)) = 0
        _SceneScale ("Scene Scale (object units per scene unit)", Float) = 0.06
        _Heading ("Heading (degrees around Y)", Range(-180, 180)) = -180
        // シーンを y 軸まわりに自動で回す速さ（0 で止まる、6 で 1 分に 1 周、負で逆回り）
        _HeadingSpeed ("Heading Speed (degrees per second)", Range(-360, 360)) = 0
        _RimWidth ("Rim Fade Width", Range(0.001, 1)) = 1

        [Header(Ground)]
        _GroundHeight ("Height (scene units below the plane)", Float) = 15
        _GroundCurvature ("Curvature (+ planet / - enclosing)", Range(-1, 1)) = 0.2
        _GroundSpeed ("Scroll Speed (scene units per second)", Float) = 5
        _GroundScale ("Pattern Scale", Float) = 2

        [Header(Fog)]
        _FogStart ("Start (scene units from the surface)", Float) = 60
        _FogEnd ("End (scene units from the surface)", Float) = 150
        _FogStrength ("Strength", Range(0, 1)) = 1

        [Header(Main Plane)]
        _MainLit ("Lit", Color) = (0.2471, 0.5098, 1, 1)
        _MainShade ("Shade", Color) = (0.1176, 0.4, 0.9608, 1)
        // カメラから見てメインの手前に重なったサブの不透明度（ディザで透かす、0 で消える）
        _CoverOpacity ("Sub Opacity In Front", Range(0, 1)) = 0.25

        [Header(Light Theme)]
        _BaseLight ("Background / Low Ground", Color) = (0.9373, 0.9451, 0.9608, 1)
        _CrustLight ("High Ground", Color) = (0.8627, 0.8784, 0.9098, 1)
        _SubLitLight ("Sub Plane Lit", Color) = (0.7373, 0.7529, 0.8, 1)
        _SubShadeLight ("Sub Plane Shade", Color) = (0.6118, 0.6275, 0.6902, 1)

        [Header(Dark Theme)]
        _BaseDark ("Background / Low Ground", Color) = (0.1176, 0.1176, 0.1804, 1)
        _CrustDark ("High Ground", Color) = (0.0667, 0.0667, 0.1059, 1)
        _SubLitDark ("Sub Plane Lit", Color) = (0.4235, 0.4392, 0.5255, 1)
        _SubShadeDark ("Sub Plane Shade", Color) = (0.2706, 0.2784, 0.3529, 1)

        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
        // 頭をメッシュの中に入れたときに、内側から見る
        // 閉じたメッシュ用で、Quad などの閉じていないメッシュではオフにする
        [ToggleUI] _InsideView ("Inside View (closed meshes)", Float) = 1
    }
    SubShader
    {
        // シーンはオブジェクト空間に置くので、頂点をワールド座標へ変換してしまうバッチングは使わない
        // （使うと、小さいメッシュでローカルの位置・回転・スケールに従わなくなる）
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "DisableBatching" = "True" }

        CGINCLUDE
        #pragma multi_compile_instancing
        #pragma target 4.5
        #include "UnityCG.cginc"
        #include "FlyingPlaneCommon.hlsl"
        #include "FlyingPlaneVat.hlsl"
        #include "FlyingPlaneBend.hlsl"
        #include "FlyingPlaneRaymarch.hlsl"
        #include "FlyingPlaneGround.hlsl"

        float _Dark, _Seed, _SceneScale, _Heading, _HeadingSpeed, _RimWidth, _InsideView;
        float _GroundHeight, _GroundCurvature, _GroundSpeed, _GroundScale;
        float _FogStart, _FogEnd, _FogStrength;
        float4 _MainLit, _MainShade;
        float _CoverOpacity;
        float4 _BaseLight, _CrustLight, _SubLitLight, _SubShadeLight;
        float4 _BaseDark, _CrustDark, _SubLitDark, _SubShadeDark;

        struct appdata
        {
            float4 vertex : POSITION;
            float3 normal : NORMAL;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4 pos : SV_POSITION;
            float3 objPos : TEXCOORD0;
            float3 objView : TEXCOORD1;   // カメラから表面への向き（オブジェクト空間、正規化前）
            float3 worldPos : TEXCOORD2;
            float3 worldNormal : TEXCOORD3;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        // テーマ（_Dark: 0 = ライト、1 = ダーク）で選んだ色
        struct Palette
        {
            float3 base;      // 背景・地形の低い面・フォグ・リムの色
            float3 crust;     // 地形の高い面
            float3 subLit;
            float3 subShade;
        };

        Palette ThemePalette()
        {
            // 途中の値は、smoothstep で緩急をつけて移る（切り替えをアニメーションしたときに、端でなめらかに止まる）
            float k = smoothstep(0, 1, saturate(_Dark));
            Palette c;
            c.base = lerp(_BaseLight.rgb, _BaseDark.rgb, k);
            c.crust = lerp(_CrustLight.rgb, _CrustDark.rgb, k);
            c.subLit = lerp(_SubLitLight.rgb, _SubLitDark.rgb, k);
            c.subShade = lerp(_SubShadeLight.rgb, _SubShadeDark.rgb, k);
            return c;
        }

        // 機体の面の色
        // メインはテーマに関わらず同じ青、サブはテーマの色
        float3 PlaneColor(PlaneHit hit, Palette palette)
        {
            if (hit.plane == 0) return lerp(_MainLit.rgb, _MainShade.rgb, hit.shade);
            return lerp(palette.subLit, palette.subShade, hit.shade);
        }

        // 距離のフォグ
        // 遠いものほど背景色へ溶かす
        float FogAmount(float distance)
        {
            return smoothstep(_FogStart, max(_FogEnd, _FogStart + 1e-3), distance) * _FogStrength;
        }

        v2f vert(appdata v)
        {
            v2f o;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
            o.pos = UnityObjectToClipPos(v.vertex);
            o.objPos = v.vertex.xyz;
            // カメラの位置をオブジェクト空間へ移すのは、インスタンスの行列が使える頂点シェーダーで行う
            o.objView = v.vertex.xyz - mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;
            o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
            o.worldNormal = UnityObjectToWorldNormal(v.normal);
            return o;
        }

        // シードの乱数（0〜1）から地形の模様の位置のずれを作るときの倍率（模様の単位）
        // VAT の再生位置は、同じ乱数にループの長さを掛けて決める
        #define SEED_GROUND_RANGE 4096.0

        // レイの始点 originObj（オブジェクト空間）から見えるシーンの色
        // surface はレイの始点からメッシュの表面までの距離（シーンの単位）
        // フォグと機体を探す距離の上限は表面から数え、カメラが離れても遠くのものが消えないようにする
        float3 ShadeScene(v2f i, float3 originObj, Palette palette, float surface)
        {
            float time = _Time.y;
            float dither = Bayer4(i.pos.xy);
            float3 random = SeedRandom(_Seed);

            // シーンの単位へ
            // 進行方向（_Heading と、_HeadingSpeed で時間とともに回る分）だけ、シーンを y 軸まわりに回す
            // 回る分は 1 周で折り返して、時間がたっても精度を保つ
            float3 rd = normalize(i.objView);
            float3 ro = originObj / _SceneScale;
            // 1 ピクセルの視野角（機体の縁と色の境目のアンチエイリアスに使う）
            float pixelAngle = max(length(ddx(rd)), length(ddy(rd)));
            float heading = -radians(_Heading + fmod(_HeadingSpeed * time, 360.0));
            rd.xz = Rotate2D(rd.xz, heading);
            ro.xz = Rotate2D(ro.xz, heading);

            // 機体は常に地形の手前に描く（地面より低いところを飛ぶ機体も、地面に隠さない）
            WorldBend bend;
            bend.height = _GroundHeight;
            bend.curvature = _GroundCurvature;
            GroundPattern pattern;
            pattern.speed = _GroundSpeed;
            pattern.scale = _GroundScale;
            pattern.offset = random.yz * SEED_GROUND_RANGE;
            GroundHit ground = TraceGround(ro, rd, bend, pattern, time, palette.base, palette.crust);
            PlaneHit edge;
            PlaneHit plane = MarchPlanes(ro, rd, CurrentFrame(time + random.x * VAT_LOOP_SECONDS), dither, bend, _CoverOpacity, surface + MAX_DIST,
                                         pixelAngle, edge);
            float3 color = palette.base;
            if (ground.hit) color = lerp(ground.color, palette.base, FogAmount(ground.distance - surface));
            if (plane.cover > 0) color = lerp(PlaneColor(plane, palette), palette.base, FogAmount(plane.distance - surface));
            // 手前の機体の縁は、覆う割合だけ重ねる
            float3 edgeColor = lerp(PlaneColor(edge, palette), palette.base, FogAmount(edge.distance - surface));
            return lerp(color, edgeColor, edge.cover);
        }

        // 外から見る: レイはカメラから（メッシュの表面は窓）
        float4 fragOutside(v2f i) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
            Palette palette = ThemePalette();
            float3 color = ShadeScene(i, i.objPos - i.objView, palette, length(i.objView) / _SceneScale);

            // リム: 面が視線に対して寝ているほど背景色へ溶かし、メッシュの縁（シーンの切れ目）を見えなくする
            float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
            float facing = abs(dot(normalize(i.worldNormal), viewDir));
            color = lerp(palette.base, color, smoothstep(0, _RimWidth, facing));
            return float4(color, 1);
        }

        // 内から見る（頭をメッシュの中に入れたとき）: レイはカメラから
        // 内側には縁がないのでリムはかけない
        float4 fragInside(v2f i) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
            if (_InsideView < 0.5) discard;
            Palette palette = ThemePalette();
            // 内側ではカメラがシーンの中にいるので、距離はカメラから数える
            return float4(ShadeScene(i, i.objPos - i.objView, palette, 0), 1);
        }
        ENDCG

        // 外から: 表面（_Cull で選ぶ面）
        Pass
        {
            Cull [_Cull]
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragOutside
            ENDCG
        }

        // 内から: 裏面
        // 外から見ているときは、先に描いた表面の深度に隠れて早めに捨てられる
        Pass
        {
            Cull Front
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragInside
            ENDCG
        }
    }
}
