using System;
using UnityEditor;
using UnityEngine;

namespace Nekochanfood.Flying
{
    /// <summary>
    /// 紙飛行機（メイン 1 機とサブ）の動きを VAT（Vertex Animation Texture）にベイクする
    /// エディタ専用ツール。出力（OutputPath）だけを Shaders フォルダへ書き出す
    ///
    /// 計算は右手系の座標（y が上、機体は +x へ進む）で行い、書き出すときだけ z を反転して Unity（左手系）へ移す
    /// 乱数は固定のシードで、動きは LoopSeconds で継ぎ目なくループする
    ///
    /// テクスチャ: 横 = 機体（メイン 1 機 + サブ FlyingPlaneVatSettings.subCount 機）× ColumnsPerPlane 列、縦 = フレーム（Fps）
    /// 単位はシーンの単位（メインの機体の原点が 0）
    /// 機体ごとの列（FlyingPlaneVat.hlsl と揃える）:
    ///   0      外接球: RGB = 中心、A = 半径（シェーダーは先にこれだけを読み、レイが当たる機体だけ頂点を読む）
    ///   1〜6   頂点: RGB = 位置、A = 機体の不透明度（シェーダーがディザで使う）
    /// </summary>
    public static class FlyingPlaneVatBaker
    {
        const string OutputPath = "Assets/nekochanfood/Shaders/Flying/FlyingPlaneVat.asset";

        /// <summary>ループの長さ(s): FlyingPlaneVat.hlsl の VAT_LOOP_SECONDS と揃える</summary>
        const int LoopSeconds = 60;
        const int Fps = 30;
        /// <summary>サブの紙飛行機のシミュレーションは、1 フレームをこの回数に分けて進める（60Hz）</summary>
        const int SimSubsteps = 2;
        const int Seed = 2027;

        const int VertsPerPlane = 6;
        const int ColumnsPerPlane = 1 + VertsPerPlane;

        [MenuItem("Tools/nekochanfood/Bake Flying Plane VAT")]
        public static void Bake()
        {
            var settings = FlyingPlaneVatSettings.LoadOrCreate();
            int frames = LoopSeconds * Fps;
            int width = (1 + settings.subCount) * ColumnsPerPlane;
            var pixels = new Color[width * frames];

            var rng = new System.Random(Seed);
            var main = new MainFlight(rng);
            var subs = SubPlaneSchedule.Run(rng, frames, main, settings, out int flights);
            for (int f = 0; f < frames; f++) WritePlane(pixels, width, f, 0, main.Vertices((float)f / Fps), 1f);

            for (int s = 0; s < subs.Length; s++)
            {
                var alpha = FadeAlpha(subs[s]);
                for (int f = 0; f < frames; f++)
                    WritePlane(pixels, width, f, 1 + s, subs[s][f].Vertices, alpha[f]);
            }

            // ループの継ぎ目の確認: メインはループの終わりの次（t = LoopSeconds）が最初と一致する
            // サブは飛び方を時間の輪の上で決めているので、継ぎ目をまたいでもつながる
            var first = main.Vertices(0f);
            var wrapped = main.Vertices(LoopSeconds);
            for (int i = 0; i < VertsPerPlane; i++)
                if (Vector3.Distance(first[i], wrapped[i]) > 1e-3f)
                    throw new InvalidOperationException($"Main plane does not loop (vertex {i}).");

            var texture = new Texture2D(width, frames, TextureFormat.RGBAFloat, false, true)
            {
                name = "FlyingPlaneVat",
                filterMode = FilterMode.Point,
                wrapMode = TextureWrapMode.Clamp,
            };
            texture.SetPixels(pixels);
            texture.Apply(false, false);
            SaveAsset(texture);
            Debug.Log($"Baked {OutputPath}: {width}x{frames} ({LoopSeconds}s @ {Fps}fps), {settings.subCount} sub planes entered {flights} times per loop");
        }

        static void WritePlane(Color[] pixels, int width, int frame, int plane, Vector3[] vertices, float alpha)
        {
            int first = frame * width + plane * ColumnsPerPlane;
            var bounds = BoundingSphere(vertices);
            pixels[first] = ToUnity(bounds, bounds.w);
            for (int i = 0; i < VertsPerPlane; i++) pixels[first + 1 + i] = ToUnity(vertices[i], alpha);
        }

        /// <summary>
        /// 頂点の平均を中心にした外接球（xyz = 中心、w = 半径）
        /// 前後のフレームを線形補間しても、頂点はこの半径の内側に収まる
        /// </summary>
        static Vector4 BoundingSphere(Vector3[] vertices)
        {
            var center = Vector3.zero;
            foreach (var v in vertices) center += v / vertices.Length;
            float radius = 0f;
            foreach (var v in vertices) radius = Mathf.Max(radius, Vector3.Distance(v, center));
            return new Vector4(center.x, center.y, center.z, radius);
        }

        /// <summary>計算に使う右手系の座標 → Unity（左手系）</summary>
        static Color ToUnity(Vector3 v, float a) => new Color(v.x, v.y, -v.z, a);

        /// <summary>既存のアセットがあれば中身だけ差し替えて、マテリアルからの参照（GUID）を保つ</summary>
        static void SaveAsset(Texture2D texture)
        {
            var existing = AssetDatabase.LoadAssetAtPath<Texture2D>(OutputPath);
            if (existing == null)
            {
                AssetDatabase.CreateAsset(texture, OutputPath);
            }
            else
            {
                EditorUtility.CopySerialized(texture, existing);
                UnityEngine.Object.DestroyImmediate(texture);
            }
            AssetDatabase.SaveAssets();
        }

        // ------------------------------------------------------------------
        // 機体の形
        // ------------------------------------------------------------------

        /// <summary>
        /// 紙飛行機のモデルの、重複を除いた頂点
        /// 順番がシェーダーの頂点番号になる
        /// （0 = 機首、1 = キールの後端、2・3 = +x の翼の付け根・先端、4・5 = -x の翼の付け根・先端）
        /// 機首が -z、翼が ±x
        /// </summary>
        static readonly Vector3[] GlbVertices =
        {
            new Vector3(0f, 0f, 0f),
            new Vector3(0f, 0f, 2f),
            new Vector3(0.10000016540288925f, 0.6375113725662231f, 2.143263578414917f),
            new Vector3(0.9000001549720764f, 0.5375113487243652f, 2.343263626098633f),
            new Vector3(-0.10000016540288925f, 0.6375113725662231f, 2.143263578414917f),
            new Vector3(-0.9000001549720764f, 0.5375113487243652f, 2.343263626098633f),
        };

        /// <summary>
        /// ロールの軸の高さ
        /// 0 = 機首の先端の高さ、1 = 機体の外接ボックスの中心
        /// 0 だと先端が動かない代わりに翼が大きく円を描き、1 だと先端が円を描く
        /// </summary>
        const float RollAxisHeight = 0.5f;

        /// <summary>
        /// ローカル座標での頂点
        /// 前後の真ん中・高さは RollAxisHeight の位置を
        /// 原点にして、機首が +z（lookAt が向ける向き）へ来るよう y 軸まわりに半回転する
        /// </summary>
        static readonly Vector3[] LocalVertices = BuildLocalVertices();

        static Vector3[] BuildLocalVertices()
        {
            var bounds = new Bounds(GlbVertices[0], Vector3.zero);
            foreach (var v in GlbVertices) bounds.Encapsulate(v);
            var c = bounds.center;
            var result = new Vector3[GlbVertices.Length];
            for (int i = 0; i < result.Length; i++)
            {
                var v = GlbVertices[i] - new Vector3(c.x, c.y * RollAxisHeight, c.z);
                result[i] = new Vector3(-v.x, v.y, -v.z);
            }
            return result;
        }

        /// <summary>機体を置く: 位置 + 回転 × (拡大 × 頂点)</summary>
        static Vector3[] Place(Vector3 position, Quaternion rotation, float scale)
        {
            var result = new Vector3[VertsPerPlane];
            for (int i = 0; i < VertsPerPlane; i++) result[i] = position + rotation * (LocalVertices[i] * scale);
            return result;
        }

        /// <summary>機首（ローカルの +z）を forward へ向け、上を +y 側にそろえる回転</summary>
        static Quaternion LookAlong(Vector3 forward) => Quaternion.LookRotation(forward, Vector3.up);

        static Quaternion RotateZ(float rad) => Quaternion.AngleAxis(rad * Mathf.Rad2Deg, Vector3.forward);

        // ------------------------------------------------------------------
        // メインの紙飛行機
        // 原点のまわりを左右・上下にゆるやかに揺れ、左右に動く向きへバンクし、上下の揺れに合わせて機首を上げ下げする
        // 傾きはどの向きにも偏らない（平均 0 の波だけで作る）
        // ------------------------------------------------------------------

        const float PlaneScale = 0.85f;
        const float MainScale = 1.5f;
        static readonly Vector2 Sway = new Vector2(1.2f, 0.6f);
        const float ForwardSpeed = 6f;
        const float PitchGain = 0.8f;
        const float RollLimit = Mathf.PI / 8f;
        const float BankShare = 0.5f;

        static float Rand(System.Random rng, float min, float max) => min + (float)rng.NextDouble() * (max - min);

        /// <summary>
        /// 周波数 f・位相 p の正弦波
        /// f は LoopSeconds でちょうど整数回まわる値に丸めて、動きがループするようにする
        /// timeScale は、時刻に掛けてから使う波（body の 2 本目は t * 2.3）のための倍率
        /// </summary>
        struct Wave
        {
            public float F, P;

            public static Wave Looping(System.Random rng, float min = 0.35f, float max = 0.8f, float timeScale = 1f)
            {
                float turns = Mathf.Max(1f, Mathf.Round(Rand(rng, min, max) * timeScale * LoopSeconds / (2f * Mathf.PI)));
                return new Wave
                {
                    F = 2f * Mathf.PI * turns / (LoopSeconds * timeScale),
                    P = Rand(rng, 0f, 2f * Mathf.PI),
                };
            }

            public float Sin(float t) => Mathf.Sin(F * t + P);
            public float Cos(float t) => Mathf.Cos(F * t + P);
        }

        class MainFlight
        {
            readonly Wave x, y, body0, body1;
            readonly float bankAmp;

            public MainFlight(System.Random rng)
            {
                x = Wave.Looping(rng);
                y = Wave.Looping(rng, 0.5f, 0.8f);
                body0 = Wave.Looping(rng);
                body1 = Wave.Looping(rng, timeScale: 2.3f);
                bankAmp = Rand(rng, 0.7f, 1f);
            }

            public Vector3[] Vertices(float t)
            {
                // グループ: 左右（z）・上下（y）に揺れ、+x へ向かって機首を上げ下げし、左右へ動く向きへバンクする
                var position = new Vector3(0f, Sway.y * y.Sin(t), Sway.x * x.Sin(t));
                float pitch = PitchGain * Sway.y * y.F * y.Cos(t) / ForwardSpeed;
                float bank = RollLimit * BankShare * bankAmp * x.Cos(t);
                var group = LookAlong(new Vector3(1f, pitch, 0f)) * RotateZ(bank);
                // ボディ: 機体だけのゆらぎの傾き
                float wobble = 0.7f * body0.Sin(t) + 0.3f * body1.Sin(t * 2.3f);
                var body = RotateZ(RollLimit * (1f - BankShare) * wobble);
                return Place(position, group * body, PlaneScale * MainScale);
            }
        }

        // ------------------------------------------------------------------
        // サブの紙飛行機
        // ------------------------------------------------------------------

        /// <summary>サブ 1 機の、1 フレームぶんの記録</summary>
        struct SubFrame
        {
            public bool Visible;
            public Vector3[] Vertices;
        }

        /// <summary>出入りのディザのフェードにかける時間(s)</summary>
        const float FadeSeconds = 0.5f;

        /// <summary>
        /// 見えている（ステージの中にいる）間を 1、外を 0 にして、出入りの前後 FadeSeconds をなめらかにつなぐ
        /// ループの終わりと始めはつながっているものとして数える（継ぎ目をまたいで飛ぶ機体も、継ぎ目でフェードしない）
        /// </summary>
        static float[] FadeAlpha(SubFrame[] frames)
        {
            int n = frames.Length;
            var alpha = new float[n];
            if (Array.TrueForAll(frames, f => f.Visible))
            {
                for (int i = 0; i < n; i++) alpha[i] = 1f;
                return alpha;
            }
            // 見えている区間の始めと終わりからの距離（フレーム）を、輪を 2 周たどって数える
            var since = new int[n];
            var until = new int[n];
            for (int k = 0; k < 2 * n; k++)
            {
                int i = k % n;
                since[i] = frames[i].Visible ? since[(i + n - 1) % n] + 1 : 0;
            }
            for (int k = 2 * n - 1; k >= 0; k--)
            {
                int i = k % n;
                until[i] = frames[i].Visible ? until[(i + 1) % n] + 1 : 0;
            }
            for (int i = 0; i < n; i++)
                alpha[i] = Mathf.SmoothStep(0f, 1f, Mathf.Min(since[i], until[i]) / (FadeSeconds * Fps));
            return alpha;
        }

        /// <summary>
        /// サブの紙飛行機の飛び方
        /// メインを中心にした球（ステージ）を基準にし、どの向きから見ても同じ条件にする
        /// サブはステージの前（+x）の端から入り、メインの横を通って後ろへ流れ、ステージの外へ出て終わる
        /// 出入りはステージの端でフェードする
        /// サブはメインにも、ほかのサブにもぶつからない（入れる前に、出ていくまでの軌道を最後まで計算して確かめる）
        ///
        /// 飛び方は、ループの長さを一周とする時間の輪の上で決める
        /// ループの終わりにはみ出す飛行は続きをループの始めに書き、空き・間隔の判定も終わりと始めをつなげて行うので、
        /// ループのどの時刻でも同じくらいの頻度で来る（継ぎ目の前後にサブが来ない時間ができない）
        /// </summary>
        class SubPlaneSchedule
        {
            /// <summary>ステージ（メインを中心にした球）の半径、この中にいる間だけ見える</summary>
            const float StageRadius = 12f;
            /// <summary>レーン: 進行方向の軸からの距離の範囲と、軸まわりの角度（水平から上下にこの角度まで）</summary>
            const float LaneRadiusMin = 2.6f, LaneRadiusMax = 5f;
            const float LaneElevationMax = 60f * Mathf.Deg2Rad;
            /// <summary>メイン・ほかのサブとの外接球どうしの、最小のすき間</summary>
            const float Clearance = 0.5f;
            /// <summary>入り始めの位置を、ステージの端からこれだけ外にする（入ってすぐフェードインが始まる）</summary>
            const float EntryMargin = 0.5f;
            /// <summary>1 回の入れ方を決めるときに試すレーンの数</summary>
            const int Tries = 30;

            // 速さ（MainSpeed はメインの前進の速さ、Speed はメインとの速さの差）・大きさ・旋回
            // 数・出現の頻度・流れの速さの倍率は FlyingPlaneVatSettings で調整する
            const float SpeedMin = 4.5f, SpeedMax = 7f;
            const float MainSpeed = 9f;
            const float ScaleMin = 0.8f, ScaleMax = 1.1f;
            const float PTurn = 0.5f;
            const float TurnStartMin = 1.5f, TurnStartMax = 3.5f;
            const float TurnDurationMin = 3f, TurnDurationMax = 5f;
            const float TurnAngleMin = 0.8f, TurnAngleMax = 1.2f;
            const float TurnBoost = 2.5f;
            const float TurnBank = 0.35f;

            // 飛んでいる間の、機首まわりのゆるやかな揺れの大きさ(rad)
            const float Roll = Mathf.PI / 8f * 0.8f;

            static float Step => 1f / (Fps * SimSubsteps);

            /// <summary>1 回の飛行の、入る前に決める値と、飛びながら変わる値</summary>
            class Flight
            {
                public Vector2 Lane;    // 進行方向の軸からのずれ（x = y 方向、y = z 方向）
                public Vector3 Pos;
                public float Age, Psi, Boost;
                public bool Turning;
                public float TurnSign, TurnStart, TurnDuration, TurnAngle;
                public float Speed, Scale;
            }

            /// <summary>決まった飛行: 機体（slot）、入るフレーム、フレームごとの記録</summary>
            struct Planned
            {
                public int Slot;
                public int Start;
                public SubFrame[] Frames;
            }

            readonly System.Random rng;
            readonly MainFlight main;
            readonly FlyingPlaneVatSettings settings;
            readonly int frames;
            readonly Wave[] rollWaves;
            /// <summary>機体ごと・フレームごとに、飛行（と出た後の待ち）で埋まっているか</summary>
            readonly bool[][] busy;
            readonly System.Collections.Generic.List<Planned> planned = new System.Collections.Generic.List<Planned>();
            /// <summary>次に入る機体のレーンの側（z の符号）、入るたびに入れ替えて、左右に偏らせない</summary>
            float nextSide;

            SubPlaneSchedule(System.Random rng, MainFlight main, FlyingPlaneVatSettings settings, int frames)
            {
                this.rng = rng;
                this.main = main;
                this.settings = settings;
                this.frames = frames;
                rollWaves = new Wave[settings.subCount];
                busy = new bool[settings.subCount][];
                for (int s = 0; s < settings.subCount; s++)
                {
                    rollWaves[s] = Wave.Looping(rng, 0.5f, 1f);
                    busy[s] = new bool[frames];
                }
                nextSide = rng.NextDouble() < 0.5 ? -1f : 1f;
            }

            /// <summary>サブの飛び方を決め、機体ごと・フレームごとの記録と、1 ループで入る回数を返す</summary>
            public static SubFrame[][] Run(System.Random rng, int frames, MainFlight main, FlyingPlaneVatSettings settings, out int flights)
            {
                var schedule = new SubPlaneSchedule(rng, main, settings, frames);
                int interval = Mathf.Max(1, Mathf.RoundToInt(settings.spawnInterval * Fps));
                for (int f = 0; f < frames; f++)
                {
                    if (!schedule.FarFromOtherStarts(f, interval)) continue;
                    schedule.TryPlace(f);
                }
                flights = schedule.planned.Count;
                return schedule.Write();
            }

            /// <summary>輪の上で、ほかの飛行の入るフレームから interval 以上離れているか</summary>
            bool FarFromOtherStarts(int frame, int interval)
            {
                foreach (var p in planned)
                {
                    int d = Mathf.Abs(p.Start - frame);
                    if (Mathf.Min(d, frames - d) < interval) return false;
                }
                return true;
            }

            /// <summary>
            /// frame に入る飛行を、空いている機体と条件に合うレーンで作る
            /// レーンの左右は入るたびに入れ替え、上下は対称な範囲から選ぶ
            /// 旋回するときは、メインから離れる側（自分のレーンの側）へ曲げる
            /// </summary>
            void TryPlace(int frame)
            {
                float side = nextSide;
                for (int i = 0; i < Tries; i++)
                {
                    float radius = Rand(rng, LaneRadiusMin, LaneRadiusMax);
                    float elevation = Rand(rng, -LaneElevationMax, LaneElevationMax);
                    var flight = new Flight
                    {
                        Lane = new Vector2(radius * Mathf.Sin(elevation), side * radius * Mathf.Cos(elevation)),
                        Speed = Rand(rng, SpeedMin, SpeedMax),
                        Scale = PlaneScale * Rand(rng, ScaleMin, ScaleMax),
                        Turning = rng.NextDouble() < PTurn,
                        TurnSign = side,
                        TurnStart = Rand(rng, TurnStartMin, TurnStartMax),
                        TurnDuration = Rand(rng, TurnDurationMin, TurnDurationMax),
                        TurnAngle = Rand(rng, TurnAngleMin, TurnAngleMax),
                    };
                    flight.Pos = new Vector3(Mathf.Sqrt(StageRadius * StageRadius - radius * radius) + EntryMargin, flight.Lane.x, flight.Lane.y);

                    int slot = FreeSlot(frame);
                    if (slot < 0) return;
                    var recorded = Fly(flight, frame, slot);
                    if (recorded == null) continue;
                    int respawn = Mathf.RoundToInt(Rand(rng, settings.respawnDelayMin, settings.respawnDelayMax) * Fps);
                    if (!SlotFree(slot, frame, recorded.Length + respawn)) continue;
                    if (!ClearOfOthers(recorded, frame)) continue;

                    for (int k = 0; k < recorded.Length + respawn; k++) busy[slot][(frame + k) % frames] = true;
                    planned.Add(new Planned { Slot = slot, Start = frame, Frames = recorded });
                    nextSide = -side;
                    return;
                }
            }

            /// <summary>frame で空いている機体（なければ -1）</summary>
            int FreeSlot(int frame)
            {
                for (int s = 0; s < busy.Length; s++) if (!busy[s][frame]) return s;
                return -1;
            }

            /// <summary>機体 slot が、frame から length フレームの間（輪の上で）空いているか</summary>
            bool SlotFree(int slot, int frame, int length)
            {
                if (length > frames) return false;
                for (int k = 0; k < length; k++) if (busy[slot][(frame + k) % frames]) return false;
                return true;
            }

            /// <summary>
            /// 同じ時間に飛ぶほかの飛行と、全フレームで外接球どうしが Clearance 以上離れているか
            /// 入るときのレーンだけでなく、旋回して横へ流れた後や速さの違いで追いつく場合も、実際の位置で確かめる
            /// </summary>
            bool ClearOfOthers(SubFrame[] recorded, int frame)
            {
                foreach (var p in planned)
                {
                    for (int k = 0; k < recorded.Length; k++)
                    {
                        // 輪の上で、frame + k が p の飛行の何フレーム目か
                        int j = ((frame + k - p.Start) % frames + frames) % frames;
                        if (j >= p.Frames.Length) continue;
                        var a = BoundingSphere(recorded[k].Vertices);
                        var b = BoundingSphere(p.Frames[j].Vertices);
                        if (Vector3.Distance(a, b) - a.w - b.w < Clearance) return false;
                    }
                }
                return true;
            }

            /// <summary>
            /// frame に入った飛行を、ステージの外へ出るまで飛ばして、フレームごとの記録を返す
            /// どこかでメインと外接球どうしが Clearance より近づくか、ループより長く飛ぶなら null
            /// </summary>
            SubFrame[] Fly(Flight flight, int frame, int slot)
            {
                var recorded = new System.Collections.Generic.List<SubFrame>();
                bool entered = false;
                for (int f = 0; f < frames; f++)
                {
                    float time = (frame + f) / (float)Fps;
                    bool inside = flight.Pos.magnitude < VisibleRadius(flight);
                    if (entered && !inside) return recorded.ToArray();
                    entered |= inside;
                    recorded.Add(new SubFrame { Visible = inside, Vertices = Pose(flight, slot, time) });
                    for (int k = 0; k < SimSubsteps; k++)
                    {
                        Advance(flight, Step);
                        var mainBounds = BoundingSphere(main.Vertices(time + (k + 1) * Step));
                        var subBounds = BoundingSphere(Pose(flight, slot, time + (k + 1) * Step));
                        if (Vector3.Distance(mainBounds, subBounds) - mainBounds.w - subBounds.w < Clearance) return null;
                    }
                }
                return null;
            }

            /// <summary>
            /// 見えなくなる距離（メインからの距離）
            /// 旋回を始めた機体は、加速してすぐステージの端に着いてしまうので、曲がって遠ざかる様子が見えるよう遠くまで見せる
            /// </summary>
            float VisibleRadius(Flight flight) =>
                flight.Turning && flight.Age > flight.TurnStart ? Mathf.Max(StageRadius, settings.turnStageRadius) : StageRadius;

            /// <summary>
            /// 時刻 time の機体の頂点
            /// 機首を進行方向（+x から psi だけ曲げた向き）へ向け、機首まわりにゆるやかに揺らし、旋回中は曲げた向きへ傾ける
            /// 揺れは機体（slot）ごとの波で、ループの長さで一周するので、継ぎ目をまたいでもつながる
            /// </summary>
            Vector3[] Pose(Flight flight, int slot, float time)
            {
                float turning = flight.Turning
                    ? Mathf.Sign(flight.Psi) * TurnBank * Mathf.Sin(Mathf.PI * Mathf.Abs(flight.Psi) / flight.TurnAngle)
                    : 0f;
                var rotation = LookAlong(new Vector3(Mathf.Cos(flight.Psi), 0f, Mathf.Sin(flight.Psi)))
                    * RotateZ(Roll * rollWaves[slot].Sin(time) + turning);
                return Place(flight.Pos, rotation, flight.Scale);
            }

            void Advance(Flight flight, float step)
            {
                flight.Age += step;
                float follow = settings.followFactor;
                if (flight.Turning)
                {
                    float u = Mathf.Clamp01((flight.Age - flight.TurnStart) / flight.TurnDuration);
                    float eased = u * u * (3f - 2f * u);
                    float psi = flight.TurnSign * flight.TurnAngle * eased;
                    flight.Boost += TurnBoost * Mathf.Abs(psi - flight.Psi);
                    flight.Psi = psi;
                    follow = Mathf.Lerp(settings.followFactor, settings.turnFollowFactor, eased);
                }
                // メインは MainSpeed で進み、自分は psi だけ曲がった向きへ進むので、メインから見ると差の分だけ後ろへ流れる
                float own = Mathf.Max(MainSpeed - flight.Speed, 0.5f) * (1f + flight.Boost);
                float move = step * follow;
                flight.Pos.x += (own * Mathf.Cos(flight.Psi) - MainSpeed) * move;
                flight.Pos.z += own * Mathf.Sin(flight.Psi) * move;
            }

            /// <summary>
            /// 決まった飛行を機体ごとのフレームへ書き込む（ループの終わりにはみ出す分は始めへ）
            /// 飛んでいないフレームは、見えない遠くに置く
            /// </summary>
            SubFrame[][] Write()
            {
                var hidden = new SubFrame { Visible = false, Vertices = Place(new Vector3(0f, -1000f, 0f), Quaternion.identity, PlaneScale) };
                var result = new SubFrame[busy.Length][];
                for (int s = 0; s < result.Length; s++)
                {
                    result[s] = new SubFrame[frames];
                    for (int f = 0; f < frames; f++) result[s][f] = hidden;
                }
                foreach (var p in planned)
                    for (int k = 0; k < p.Frames.Length; k++) result[p.Slot][(p.Start + k) % frames] = p.Frames[k];
                return result;
            }
        }
    }
}
