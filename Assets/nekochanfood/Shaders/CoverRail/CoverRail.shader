// ============================================================================
//  CoverRail
//  カバーアートを横一列に並べて見せる、レイマーチングのシェーダー
// ============================================================================
//
//  [概要]
//   ・中央の 1 枚が正面を向き、左右のカバーは斜めに重なって並ぶ
//   ・平面のパネル（Quad など）を「窓」にして、その奥の 3D シーンを描く
//   ・床に映り込みがある（床で反射させたレイをもう一度飛ばす）
//   ・見ている人が横へ動くと、カバーが 1 枚ずつスクロールする（power4.out, 0.75 秒）
//   ・カバーの絵はアトラスから 1 枚ずつ選ぶ
//
//  [表示モード]
//   3D（既定）  見ている人の目からシーンを見る（見る位置で視差が変わる）
//   2D          パネル正面の仮想カメラから見た絵を、平面の絵として映す
//
//  [パネルの条件]
//   原点が中心の四角形で、UV 0..1 が四角形全体、x が横（u）、y が縦（v）。
//   大きさは頂点と UV から、向きと縮尺はトランスフォームから求めるので、
//   どんな向き・大きさ・縦横比でも、中央のカバーがパネルの中心に来る。
//
//  [シーンの座標]
//   単位: カバー 1 枚の幅 = 1（= パネルの短い辺 × _CoverSize）
//   床は y = 0。中央のカバーは z = 0 で +z（パネルの手前）を向き、下端が床に接する。
//   パネルの中心は (0, 0.5, _Recess)。
//
//  [スクロールの履歴]
//   見ている人の位置の履歴は CoverRailHistory.shader の CustomRenderTexture から読む。
//   履歴が更新されていないとき（エディタで再生していないときなど）は、
//   アニメーションなしで今の位置に合わせる。
// ============================================================================
Shader "nekochanfood/CoverRail"
{
    Properties
    {
        [NoScaleOffset] _Atlas ("Cover Atlas", 2D) = "gray" {}
        [IntRange] _AtlasCells ("Atlas Cells Per Side", Range(1, 16)) = 8
        // カバーの絵の選び方が変わる
        [IntRange] _Seed ("Seed", Range(0, 9999)) = 0
        _Background ("Background", Color) = (0, 0, 0, 1)

        [Header(Scroll)]
        [NoScaleOffset] _History ("Viewer History (CoverRailHistory CRT)", 2D) = "black" {}
        // 1 枚進むのに必要な横の移動（カバーの幅が 1）
        // カバーの大きさを基準にするので、パネルを横に伸ばしても反応は変わらない
        _ScrollStep ("Viewer Move Per Cover", Float) = 0.4
        _ScrollOffset ("Offset (covers)", Float) = 0
        _ScrollDuration ("Duration (seconds)", Float) = 0.75
        // オフ（定点）: 中央のカバーはパネルの中心にあり、カバーの列が流れる
        // オン（追従）: 中央のカバーが、見ている人の正面へ（同じアニメーションで）付いてくる
        [ToggleUI] _Follow ("Follow Viewer", Float) = 0

        [Header(Projection)]
        // オフ（3D）: パネルを窓にして、見ている人の目からシーンを見る（見る位置で視差が変わる）
        // オン（2D）: パネルの正面に固定した仮想のカメラから見た絵を、パネルに平面の絵として映す
        [ToggleUI] _Projection2D ("2D Projection", Float) = 0
        // 2D のときの仮想のカメラの、パネルの面からの距離（カバーの幅が 1）
        _VirtualDistance ("2D Camera Distance", Float) = 3

        [Header(Layout)]
        // カバーの大きさ（パネルの短い辺に対する割合）
        _CoverSize ("Cover Size", Range(0.1, 1)) = 0.55
        // 中央のカバーがパネルの面からどれだけ奥にあるか（カバーの幅が 1）
        _Recess ("Depth Behind Panel", Float) = 0.6
        _CenterGap ("Center Gap", Float) = 0.9
        // 脇のカバーの間隔（追従のときは Viewer Move Per Cover と同じ間隔になり、脇のカバーはその場に止まる）
        _Spacing ("Side Spacing", Float) = 0.18
        _SideAngle ("Side Angle", Range(0, 89)) = 60
        _SideDepth ("Side Depth", Float) = 0.8
        _Thickness ("Cover Thickness", Range(0.002, 0.1)) = 0.015
        _SideBrightness ("Side Brightness", Range(0, 1)) = 0.75
        _EdgeColor ("Cover Edge", Color) = (0.12, 0.12, 0.12, 1)

        [Header(Reflection)]
        _ReflectionStrength ("Strength", Range(0, 1)) = 0.35
        // カバーの下端からこの高さまでで映り込みが消える
        _ReflectionFade ("Fade Height", Range(0.05, 1)) = 0.6

        [Header(Edge Fade)]
        // パネルの左右の端から、この幅（パネルの短い辺が 1）で背景色へ溶かす
        _EdgeFade ("Width", Range(0, 1)) = 0.25
    }
    SubShader
    {
        // パネルの大きさと向きはメッシュのトランスフォームから求めるので、頂点をワールド座標へ変換してしまうバッチングは使わない
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "DisableBatching" = "True" }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma target 3.5
            #include "UnityCG.cginc"

            #define MAX_STEPS 96
            #define NEIGHBORS 2
            // 目標のカバーは、今の目標から 0.5 + この値だけ離れたら切り替える（境目で行き来しない）
            #define SCROLL_HYSTERESIS 0.1
            // 履歴の一番新しい記録がこれより古ければ、履歴は更新されていない
            #define HISTORY_TIMEOUT 0.5

            sampler2D _Atlas;
            float4 _Atlas_TexelSize;
            sampler2D _History;
            float4 _History_TexelSize;
            float _AtlasCells, _Seed;
            float4 _Background, _EdgeColor;
            float _ScrollStep, _ScrollOffset, _ScrollDuration, _Follow;
            float _Projection2D, _VirtualDistance;
            float _CoverSize, _Recess, _CenterGap, _Spacing, _SideAngle, _SideDepth, _Thickness, _SideBrightness;
            float _ReflectionStrength, _ReflectionFade, _EdgeFade;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 scenePos : TEXCOORD0;                     // 表面の位置（シーンの座標）
                nointerpolation float3 sceneCamera : TEXCOORD1;  // カメラ（この目）の位置（シーンの座標）
                nointerpolation float scroll : TEXCOORD2;
                float2 edge : TEXCOORD3;   // パネルの左端・右端までの距離（パネルの短い辺が 1）
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // ワールドからシーンへの変換と、スクロールの向き
            struct Panel
            {
                float3 center;
                float3 right, up, toward;   // ワールドの単位ベクトル（toward はパネルの表から手前へ）
                float unit;                 // シーンの 1（カバーの幅）のワールドの長さ
                float aspect;               // 横 / 短い辺
            };

            // 四角形の頂点 1 つから、パネル全体の大きさと向きを求める
            // 原点が中心で UV が四角形全体なので、頂点の位置 / (UV - 0.5) がパネルの大きさ（符号は UV の向き）
            Panel MakePanel(float3 vertex, float2 uv)
            {
                float3 axisX = unity_ObjectToWorld._m00_m10_m20;
                float3 axisY = unity_ObjectToWorld._m01_m11_m21;
                float2 size = vertex.xy / (uv - 0.5);
                Panel p;
                p.center = unity_ObjectToWorld._m03_m13_m23;
                p.right = normalize(axisX) * sign(size.x);
                p.up = normalize(axisY) * sign(size.y);
                // UV が裏返らずに見える側が手前
                p.toward = normalize(cross(p.up, p.right));
                float2 sizeWorld = abs(size) * float2(length(axisX), length(axisY));
                float shortSide = min(sizeWorld.x, sizeWorld.y);
                p.unit = shortSide * _CoverSize;
                p.aspect = sizeWorld.x / shortSide;
                return p;
            }

            float3 ToScene(Panel p, float3 world)
            {
                float3 d = world - p.center;
                return float3(dot(d, p.right), dot(d, p.up), dot(d, p.toward)) / p.unit + float3(0, 0.5, _Recess);
            }

            // VR では両目の真ん中（目ごとにスクロールがずれないように）
            float3 CenterEyePos()
            {
            #if defined(USING_STEREO_MATRICES)
                return (unity_StereoWorldSpaceCameraPos[0] + unity_StereoWorldSpaceCameraPos[1]) * 0.5;
            #else
                return _WorldSpaceCameraPos;
            #endif
            }

            // 見ている人の位置での、スクロールの位置（カバーの番号、連続）
            float ScrollAt(Panel p, float3 viewer)
            {
                return dot(viewer - p.center, p.right) / (p.unit * max(_ScrollStep, 1e-3));
            }

            // power4.out（1 - (1 - x)^5）
            float Power4Out(float x)
            {
                float r = 1 - saturate(x);
                float r2 = r * r;
                return 1 - r2 * r2 * r;
            }

            // 時刻 start に from から to へ動き出したスクロールの、時刻 time での位置
            float Animate(float from, float to, float start, float time)
            {
                return lerp(from, to, Power4Out((time - start) / max(_ScrollDuration, 1e-3)));
            }

            // 履歴を古い順にたどり、目標のカバーが変わるたびに、そのときの位置から新しい目標へ動き直す
            float Scroll(Panel p)
            {
                float count = _History_TexelSize.z;
                float4 newest = tex2Dlod(_History, float4(0.5 / count, 0.5, 0, 0));
                if (newest.w <= 0 || abs(_Time.y - newest.w) > HISTORY_TIMEOUT)
                    return round(ScrollAt(p, CenterEyePos())) + _ScrollOffset;

                float target = 0, from = 0, start = -1e9;
                bool started = false;
                [loop]
                for (float k = count - 1; k >= 0; k--)
                {
                    float4 sample = tex2Dlod(_History, float4((k + 0.5) / count, 0.5, 0, 0));
                    if (sample.w <= 0) continue;   // まだ書かれていない
                    float s = ScrollAt(p, sample.xyz);
                    if (!started)
                    {
                        target = from = round(s);
                        started = true;
                    }
                    else if (abs(s - target) > 0.5 + SCROLL_HYSTERESIS)
                    {
                        from = Animate(from, target, start, sample.w);
                        target = round(s);
                        start = sample.w;
                    }
                }
                return Animate(from, target, start, _Time.y) + _ScrollOffset;
            }

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                Panel p = MakePanel(v.vertex.xyz, v.uv);
                o.scenePos = ToScene(p, mul(unity_ObjectToWorld, v.vertex).xyz);
                // 2D: パネルの中心の正面に固定した仮想のカメラ（目の位置によらず同じ絵になる）
                o.sceneCamera = _Projection2D > 0.5 ? float3(0, 0.5, _Recess + max(_VirtualDistance, 0.01))
                                                    : ToScene(p, _WorldSpaceCameraPos);
                o.scroll = Scroll(p);
                o.edge = float2(v.uv.x, 1 - v.uv.x) * p.aspect;
                return o;
            }

            float Hash(float n)
            {
                return frac(sin(n * 12.9898 + _Seed * 78.233) * 43758.5453);
            }

            // y 軸まわりの回転（カバーのローカルからシーンへ: ローカルの +z が (sin a, cos a) を向く）
            float2 RotY(float2 xz, float a)
            {
                float c = cos(a), s = sin(a);
                return float2(xz.x * c + xz.y * s, -xz.x * s + xz.y * c);
            }

            float SdRoundBox(float3 q, float3 halfSize, float r)
            {
                float3 d = abs(q) - halfSize + r;
                return length(max(d, 0)) + min(max(d.x, max(d.y, d.z)), 0) - r;
            }

            // 中央からの番号の差 d（スクロールで連続に変わる）にあるカバーの置き方
            // 中央から脇へ移る 1 枚分の間は、位置・奥行き・角度を d に比例して移す（動きの緩急はスクロールの power4.out がつける）
            struct Cover
            {
                float3 center;
                float angle;
                float side;    // 0 = 中央で正面、1 = 脇で斜め
            };

            // 脇のカバーの間隔
            // 追従では列全体が 1 枚ごとに _ScrollStep ずつ横へ動くので、間隔を同じにして脇のカバーをワールドに止める
            // （間隔が違うと、脇のカバーは 1 枚ごとに (_ScrollStep - 間隔) だけ逆向きに動き、
            //   中央へ入るときの動きと向きが入れ替わって行ったり来たりする）
            float SideSpacing()
            {
                return max(_Follow > 0.5 ? _ScrollStep : _Spacing, 1e-3);
            }

            Cover Layout(float d)
            {
                float a = abs(d);
                float s = d < 0 ? -1 : 1;
                Cover c;
                c.side = saturate(a);
                c.center = float3(s * (_CenterGap * c.side + max(a - 1, 0) * SideSpacing()), 0.5, -_SideDepth * c.side);
                // 脇のカバーは中央へ顔を向ける（外側の縁が手前に来る）
                c.angle = -s * radians(_SideAngle) * c.side;
                return c;
            }

            // 点の x から近いカバーの番号を見積もる（その前後 NEIGHBORS 枚だけを調べる）
            float NearestIndex(float3 p, float scroll)
            {
                float ax = abs(p.x);
                float d = ax < _CenterGap ? ax / _CenterGap : 1 + (ax - _CenterGap) / SideSpacing();
                return round(scroll + (p.x < 0 ? -d : d));
            }

            // カバーの列の距離関数（マーチの各歩では距離だけを求める）
            float MapDistance(float3 p, float scroll)
            {
                float n0 = NearestIndex(p, scroll);
                float3 halfSize = float3(0.5, 0.5, _Thickness * 0.5);
                float best = 1e9;
                [unroll]
                for (int k = -NEIGHBORS; k <= NEIGHBORS; k++)
                {
                    Cover c = Layout(n0 + k - scroll);
                    float3 q = p - c.center;
                    q.xz = RotY(q.xz, -c.angle);
                    best = min(best, SdRoundBox(q, halfSize, _Thickness * 0.5));
                }
                return best;
            }

            // 当たった点で、いちばん近いカバーの番号とローカル座標を求める（MapDistance と同じ順で比べる）
            float MapCovers(float3 p, float scroll, out float index, out float3 local)
            {
                float n0 = NearestIndex(p, scroll);
                float3 halfSize = float3(0.5, 0.5, _Thickness * 0.5);
                float best = 1e9;
                index = n0;
                local = 0;
                [unroll]
                for (int k = -NEIGHBORS; k <= NEIGHBORS; k++)
                {
                    float i = n0 + k;
                    Cover c = Layout(i - scroll);
                    float3 q = p - c.center;
                    q.xz = RotY(q.xz, -c.angle);
                    float dist = SdRoundBox(q, halfSize, _Thickness * 0.5);
                    if (dist < best)
                    {
                        best = dist;
                        index = i;
                        local = q;
                    }
                }
                return best;
            }

            // カバーが置かれうる範囲（y と z の厚み）にレイが入っている区間
            // yMax より上は調べない（映り込みは _ReflectionFade より上では見えないので、そこで打ち切れる）
            float2 CoverRange(float3 ro, float3 rd, float yMax)
            {
                float2 lo = float2(-0.01, -_SideDepth - 0.6);
                float2 hi = float2(yMax, 0.6);
                float2 inv = 1 / rd.yz;
                float2 t0 = (lo - ro.yz) * inv, t1 = (hi - ro.yz) * inv;
                float2 tn = min(t0, t1), tf = max(t0, t1);
                return float2(max(max(tn.x, tn.y), 0), min(tf.x, tf.y));
            }

            struct Hit
            {
                bool hit;
                float t;
                float index;
                float3 local;    // カバーのローカル座標（中心が原点、表が +z）
            };

            // カバーが実際に来る一番手前の z
            // 中央から脇へ移る途中のカバーの手前の縁は -D s + 0.5 sin(θ s)（s = 0..1、D = 奥行き、θ = 脇の角度）で、その最大に厚みを足す
            float CoversFront()
            {
                float theta = max(radians(_SideAngle), 1e-4);
                float depth = _SideDepth;
                float s = saturate(acos(clamp(2 * depth / theta, -1, 1)) / theta);
                float front = max(max(0, -depth + 0.5 * sin(theta)), -depth * s + 0.5 * sin(theta * s));
                return front + 0.5 * _Thickness + 0.01;
            }

            Hit March(float3 ro, float3 rd, float scroll, float pixelAngle, float tMax, float yMax)
            {
                Hit h;
                h.hit = false;
                h.t = tMax;
                h.index = 0;
                h.local = 0;
                float2 range = CoverRange(ro, rd, yMax);
                float t = range.x;
                tMax = min(tMax, range.y);
                // 1 歩の上限: 調べていないカバー（前後 NEIGHBORS 枚より外）までの最短の距離
                // （その次の脇のカバーの中心までの x の差から、斜めになったカバーの横の半幅を引く）
                float maxStep = max((NEIGHBORS + 0.5) * SideSpacing() - 0.5 * cos(radians(_SideAngle)) - _Thickness, 0.02);
                // カバーの一番手前（CoversFront）より 1 歩以上手前では、距離は必ず 1 歩の上限より大きく、ちょうど上限ずつ進む
                // その歩数をまとめて飛ばす（歩く点は 1 歩ずつ進んだときと同じなので、当たり方は変わらない）
                int s = 0;
                if (rd.z < 0)
                {
                    float tSafe = (CoversFront() - ro.z) / rd.z - maxStep / -rd.z;
                    s = (int)clamp(floor((tSafe - t) / maxStep) + 1, 0, MAX_STEPS);
                    t += s * maxStep;
                }
                [loop]
                for (; s < MAX_STEPS && t < tMax; s++)
                {
                    float d = MapDistance(ro + rd * t, scroll);
                    if (d < max(t * pixelAngle * 0.3, 1e-4))
                    {
                        h.hit = true;
                        h.t = t;
                        break;
                    }
                    t += min(d, maxStep);
                }
                if (h.hit) MapCovers(ro + rd * h.t, scroll, h.index, h.local);
                return h;
            }

            // 当たったカバーの色
            // distance はカメラからレイが進んだ長さ（反射なら床までを足す）で、画素の大きさを見積もるのに使う
            // coverage は縁のアンチエイリアスで、画素のうちカバーが覆う割合
            float3 CoverColor(Hit h, float3 rd, float distance, float scroll, float pixelAngle, out float coverage)
            {
                Cover c = Layout(h.index - scroll);
                float3 q = h.local;
                float3 rdl = rd;
                rdl.xz = RotY(rd.xz, -c.angle);
                float facing = max(abs(rdl.z), 0.2);
                float pixel = distance * pixelAngle;
                float brightness = lerp(1, _SideBrightness, c.side);

                // 縁は、画素の大きさ（面の上で、斜めなら引き伸ばす）に対する縁までの距離で覆う割合を決める
                coverage = saturate((0.5 - max(abs(q.x), abs(q.y))) / (pixel / facing) + 0.5);

                // 表でなければ（厚みの面・裏）縁の色
                if (q.z < _Thickness * 0.25) return _EdgeColor.rgb * brightness;

                // アトラスから 1 枚を選ぶ。乱数だと同じ絵が近くに並ぶので、歩幅 25（64 と互いに素、16 とも互いに素）で巡らせる
                // 隣り合うカバーは必ず違う絵になり、アトラスが 16 枚の繰り返しでも同じ絵は 16 枚以上離れる
                float cells = _AtlasCells;
                float count = cells * cells;
                float cell = fmod(fmod(h.index * 25 + _Seed, count) + count, count);
                float2 cellXY = float2(fmod(cell, cells), floor(cell / cells));
                float cellTexels = _Atlas_TexelSize.w / cells;
                // ミップは画素の大きさから選び、隣のセルが混ざらないよう、その段の半テクセルだけ内側に寄せる
                float lod = max(log2(pixel * rsqrt(facing) * cellTexels), 0);
                float inset = min(0.5 * exp2(lod) / cellTexels, 0.5);
                float2 uv = clamp(q.xy + 0.5, inset, 1 - inset);
                return tex2Dlod(_Atlas, float4((cellXY + uv) / cells, 0, lod)).rgb * brightness;
            }

            // レイの区間 [tStart, tEnd] に見えるカバーの色と、画素を覆う割合
            // mirrored のときは、床（y = 0）で上下を反転したカバーの複製（映り込み）を見て、下端ほど濃く背景色に重ねた色を返す
            float3 Trace(float3 ro, float3 rd, float scroll, float pixelAngle, float tStart, float tEnd, bool mirrored, out float coverage)
            {
                coverage = 0;
                float3 origin = ro + rd * tStart;
                if (mirrored)
                {
                    origin.y = -origin.y;
                    rd.y = -rd.y;
                }
                // 映り込みは _ReflectionFade の高さで消えるので、上へ向かうレイはそこで打ち切る
                // （その上で当たっても色は背景色のまま。上から下りてくるレイは、上で当たったカバーが下を隠すので打ち切らない）
                float yMax = mirrored && rd.y > 0 ? min(_ReflectionFade + 0.05, 1.01) : 1.01;
                Hit h = March(origin, rd, scroll, pixelAngle, tEnd - tStart, yMax);
                if (!h.hit) return 0;
                float3 color = CoverColor(h, rd, tStart + h.t, scroll, pixelAngle, coverage);
                if (!mirrored) return color;
                float height = origin.y + rd.y * h.t;
                return lerp(_Background.rgb, color, _ReflectionStrength * (1 - smoothstep(0, _ReflectionFade, height)));
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float scroll = i.scroll;
                // 追従: カバーの列を、中央のカバーがスクロールの位置（見ている人の横の位置を 1 枚ずつに区切ったところ）に来るよう横へずらす
                float follow = _Follow > 0.5 ? (scroll - _ScrollOffset) * _ScrollStep : 0;
                float3 ro = i.sceneCamera;
                // 2D の仮想のカメラも、中央のカバーと一緒に横へ動く（端でも中央のカバーを正面から見る）
                ro.x += _Projection2D > 0.5 ? follow : 0;
                float3 rd = normalize(i.scenePos - ro);
                // 1 ピクセルの視野角（縁のアンチエイリアスとミップの選択に使う）
                float pixelAngle = max(length(ddx(rd)), length(ddy(rd)));
                // シーンを動かす代わりにレイの始点を逆へずらす（床は横に一様なので変わらない）
                ro.x -= follow;

                // 床の面でレイを 2 つの区間に分ける
                // 目が床より上: 手前は実物のカバー、床から先は床で反射したレイ（= 上下を反転した複製）で映り込み
                // 目が床より下: 手前は上下を反転した複製（映り込み）、床を越えた先は実物のカバー（見上げても映り込みが残る）
                float floorT = -ro.y / rd.y;
                floorT = floorT > 0 ? floorT : 1e5;
                bool below = ro.y < 0;
                float coverage;
                float3 near = Trace(ro, rd, scroll, pixelAngle, 0, floorT, below, coverage);
                float3 color = _Background.rgb;
                // 手前で覆われきった画素では、先の区間は飛ばさない
                if (floorT < 1e5 && coverage < 1)
                {
                    float farCoverage;
                    float3 far = Trace(ro, rd, scroll, pixelAngle, floorT, 1e5, !below, farCoverage);
                    color = lerp(color, far, farCoverage);
                }
                color = lerp(color, near, coverage);
                // 左右の端を背景色へ溶かす
                float fade = smoothstep(0, max(_EdgeFade, 1e-4), min(i.edge.x, i.edge.y));
                return float4(lerp(_Background.rgb, color, fade), 1);
            }
            ENDCG
        }
    }
}
